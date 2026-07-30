set shell := ['bash', '-uc']
set windows-shell := ['cmd', '/c']

name := 'rarity'
src_dir := 'src'
assets_dir := 'assets'
fonts_dir := assets_dir + '/fonts'
shaders_dir := assets_dir + '/shaders'
out_dir := 'bin'

# These shouldn't need to be changed

ext := if os_family() == 'windows' { '.exe' } else { '' }
debug_suffix := '_debug'
odin_exe := 'odin'
odin_args := '-vet -vet-cast -vet-tabs -strict-style'
build_args := odin_args + ' -keep-executable -microarch:native'
debug_args := build_args + ' -debug'
release_args := build_args + ' -o:speed'
slang_args := "-I " + shaders_dir + " -profile glsl_460 -matrix-layout-column-major"

# Default recipe which runs `build-release`
default: build-release

_init:
    @just _init-{{ os_family() }}

_init-windows:
    @-mkdir {{ out_dir }} >nul 2>nul

_init-unix:
    @-mkdir -p {{ out_dir }} >/dev/null 2>&1

# Cleans the build directory
clean:
    @just _clean-{{ os_family() }}

_clean-windows:
    -rmdir /S /Q "{{ out_dir }}" >nul 2>nul
# Fine.
# -del /S /Q "{{ replace(fonts_dir, '/', '\') }}\*.json" "{{ replace(fonts_dir, '/', '\') }}\*.png" "{{ replace(fonts_dir, '/', '\') }}\*.arfont" >nul 2>nul
# -del /S /Q "{{ replace(shaders_dir, '/', '\') }}\*.glsl" "{{ replace(shaders_dir, '/', '\') }}\*.spv" >nul 2>nul

_clean-unix:
    -rm -f "{{ out_dir }}" >/dev/null 2>&1
    -rm -f "{{ fonts_dir }}/*.json" "{{ fonts_dir }}/*.png" "{{ fonts_dir }}/*.arfont" >/dev/null 2>&1
    -rm -f "{{ shaders_dir }}/*.glsl" "{{ shaders_dir }}/*.spv" >/dev/null 2>&1

_compile-shader name type entry *args:
    slangc {{ shaders_dir }}/{{ name }}.slang -g -target spirv {{ slang_args }} -o {{ shaders_dir }}/{{ name }}.{{ type }}.spv -target glsl {{ slang_args }} -o {{ shaders_dir }}/{{ name }}.{{ type }}.glsl -entry {{ entry }} {{ args }}

# Compiles the slang shaders. Requires slangc
build-shaders *args:
    @just _compile-shader model vert vertex_main {{ args }}
    @just _compile-shader model frag fragment_main {{ args }}
    @just _compile-shader edge_detect vert vertex_main {{ args }}
    @just _compile-shader edge_detect frag fragment_main {{ args }}
    @just _compile-shader edge_detect_overlay vert vertex_main {{ args }}
    @just _compile-shader edge_detect_overlay frag fragment_main {{ args }}
    @just _compile-shader screen vert vertex_main {{ args }}
    @just _compile-shader screen frag fragment_main {{ args }}
    @just _compile-shader msdf vert vertex_main {{ args }}
    @just _compile-shader msdf frag fragment_main {{ args }}

alias shaders := build-shaders

_build-font font size="16" format="png" *args:
    msdf-atlas-gen -font {{ fonts_dir }}/{{ font }}.ttf -size {{ size }} -format {{ format }} -json {{ fonts_dir }}/{{ font }}.json -imageout {{ fonts_dir }}/{{ font }}.{{ format }} -arfont {{ fonts_dir }}/{{ font }}.arfont {{ args }}

# Compiles the fonts. Requires msdf-atlas-gen
build-fonts *args:
    @just _build-font Miracode 32 png -emrange 0.3 {{ args }}
    @just _build-font Inter-Regular 32 png -emrange 0.3 {{ args }}
    @just _build-font Monocraft 32 png -emrange 0.3 -type mtsdf {{ args }}

alias fonts := build-fonts

# Compiles all assets
build-assets: build-shaders build-fonts

alias assets := build-assets

# Compiles with debug profile
build-debug *args: _init
    {{ odin_exe }} build {{ src_dir }} -out:{{ out_dir }}/{{ name }}{{ debug_suffix }}{{ ext }} {{ debug_args }} {{ args }}

# Compiles with release profile
build-release *args: _init
    {{ odin_exe }} build {{ src_dir }} -out:{{ out_dir }}/{{ name }}{{ ext }} {{ release_args }} {{ args }}

alias build := build-release

# Runs `odin check`
check *args:
    {{ odin_exe }} check {{ src_dir }} {{ odin_args }} {{ args }}

# Runs the application with debug profile
run-debug *args: _init
    {{ odin_exe }} run {{ src_dir }} -out:{{ out_dir }}/{{ name }}{{ debug_suffix }}{{ ext }} {{ debug_args }} {{ args }}

alias debug := run-debug

# Runs the application with release profile
run-release *args: _init
    {{ odin_exe }} run {{ src_dir }} -out:{{ out_dir }}/{{ name }}{{ ext }} {{ release_args }} {{ args }}

alias run := run-release
