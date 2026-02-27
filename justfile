set shell := ['bash', '-uc']
set windows-shell := ['cmd', '/c']

name := 'rarity'
src_dir := 'src'
shaders_dir := 'shaders'
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
    -rmdir /S /Q {{ out_dir }} >nul 2>nul

_clean-unix:
    -rm -f {{ out_dir }} >/dev/null 2>&1

# Compiles the slang shaders. Requires slangc
build-shaders *args:
    slangc {{ shaders_dir }}/basic.slang -g -target spirv {{ slang_args }} -o {{ shaders_dir }}/basic.vert.spv -target glsl {{ slang_args }} -o {{ shaders_dir }}/basic.vert.glsl -entry vertexMain {{ args }}
    slangc {{ shaders_dir }}/basic.slang -g -target spirv {{ slang_args }} -o {{ shaders_dir }}/basic.frag.spv -target glsl {{ slang_args }} -o {{ shaders_dir }}/basic.frag.glsl -entry fragmentMain {{ args }}

alias shaders := build-shaders

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
