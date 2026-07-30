package artery

import "core:bytes"
import "core:image"
@(require) import "core:image/bmp"
@(require) import "core:image/png"
@(require) import "core:image/tga"
import "core:io"
import "core:log"
import "core:os"
import "core:slice"

_ :: bmp
_ :: png
_ :: tga

HEADER_TAG :: "ARTERY/FONT\x00\x00\x00\x00\x00"
HEADER_VERSION :: 1
HEADER_MAGIC_NUM :: 0x4d276a5c
HEADER_REAL_TYPE :: Real_Type.Float
FOOTER_MAGIC_NUM :: 0x55ccb363

Font_Flag :: enum u32le {
	Bold,
	Light,
	Extra_Bold,
	Condensed,
	Italic,
	Small_Caps,
	_,
	_,
	_,
	Iconographic,
	Sans_Serif,
	Serif,
	Monospace,
}
Font_Flags :: bit_set[Font_Flag;u32le]

Codepoint_Type :: enum u32le {
	Unspecified  = 0,
	Unicode      = 1,
	Indexed      = 2,
	Iconographic = 14,
}

Metadata_Format :: enum u32le {
	None      = 0,
	Plaintext = 1,
	Json      = 2,
}

Image_Type :: enum u32le {
	None              = 0,
	Srgb_Image        = 1,
	Linear_Mask       = 2,
	Masked_Srgb_Image = 3,
	Sdf               = 4,
	Psdf              = 5,
	Msdf              = 6,
	Mtsdf             = 7,
	Mixed_Content     = 255,
}

Pixel_Format :: enum u32le {
	Unknown   = 0,
	Boolean1  = 1,
	Unsigned8 = 8,
	Float32   = 32,
}

Image_Encoding :: enum u32le {
	Unknown_Encoding = 0,
	Raw_Binary       = 1,
	Bmp              = 4,
	Tiff             = 5,
	Png              = 8,
	Tga              = 9,
}

Image_Orientation :: enum i32le {
	Top_Down  = 1,
	Bottom_Up = -1,
}

Real_Type :: enum u32le {
	Float  = 0x14,
	Double = 0x18,
}

Data_Error :: enum {
	None,
	Not_An_Artery_File,
	Invalid_Magic,
	Invalid_Version,
	Unsupported_Real_Type,
	Multiple_Images_Unsupported,
	Unsupported_Image_Type,
	Invalid_Variant_Section_Length,
	Unknown_Encoding,
	Unsupported_Pixel_Format,
	Invalid_Image_Section_Length,
	Invalid_Appendix_Section_Length,
	Invalid_Checksum,
	Data_Left_Over,
}

Error :: union #shared_nil {
	Data_Error,
	os.Error,
	io.Error,
	image.Error,
}

Metrics :: struct {
	font_size:                        f32,
	distance_range:                   f32,
	em_size:                          f32,
	ascender, descender:              f32,
	line_height:                      f32,
	underline_y, underline_thickness: f32,
	distance_range_middle:            f32,
}

Bounds :: struct {
	left, bottom, right, top: f32,
}

Advance :: struct {
	h, v: f32,
}

Glyph :: struct {
	codepoint:    u32,
	image:        u32, // TODO: Support multiple images (3D sampler?)
	plane_bounds: Bounds,
	image_bounds: Bounds,
	advance:      Advance,
}

Kern_Pair :: struct {
	left, right: u32,
	advance:     Advance,
}

Font_Variant :: struct {
	flags:            Font_Flags,
	weight:           u32,
	codepoint_type:   Codepoint_Type,
	image_type:       Image_Type,
	fallback_variant: u32,
	fallback_glyph:   u32,
	metrics:          Metrics,
	name:             string,
	metadata:         string,
	glyphs:           []Glyph,
	kern_pairs:       []Kern_Pair,
}

Image :: struct {
	encoding:      Image_Encoding,
	width, height: u32,
	channels:      u32,
	pixel_format:  Pixel_Format,
	image_type:    Image_Type,
	child_images:  u32,
	metadata:      string,
	data:          []byte `fmt:"-"`, // R8G8B8A8 data. *always*
}

Appendix :: struct {
	metadata: string,
	data:     []byte `fmt:"-"`,
}

Font :: struct {
	metadata_format: Metadata_Format,
	metadata:        string,
	variants:        []Font_Variant,
	images:          []Image,
	appendices:      []Appendix,
}

destroy_font :: proc(font: ^Font) {
	delete(font.metadata)

	for variant in font.variants {
		delete(variant.metadata)
		delete(variant.glyphs)
		delete(variant.kern_pairs)
	}
	delete(font.variants)

	for image in font.images {
		delete(image.metadata)
		delete(image.data)
	}
	delete(font.images)

	for appendix in font.appendices {
		delete(appendix.metadata)
		delete(appendix.data)
	}
	delete(font.appendices)

	font^ = {}
}

load_font_from_path :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	font: Font,
	err: Error,
) {
	file_data, read_err := os.read_entire_file(path, context.temp_allocator)
	log.ensuref(read_err == nil, "Could not open '{}': {}", path, read_err)
	return load_font_from_memory(file_data, allocator)
}

load_font_from_memory :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	font: Font,
	err: Error,
) {
	LE_Metrics :: struct {
		font_size:                        f32le,
		distance_range:                   f32le,
		em_size:                          f32le,
		ascender, descender:              f32le,
		line_height:                      f32le,
		underline_y, underline_thickness: f32le,
		distance_range_middle:            f32le,
		__reserved:                       [23]f32le `fmt:"-"`,
	}

	LE_Bounds :: struct {
		left, bottom, right, top: f32le,
	}

	LE_Advance :: struct {
		h, v: f32le,
	}

	LE_Glyph :: struct {
		codepoint:    u32le,
		image:        u32le,
		plane_bounds: LE_Bounds,
		image_bounds: LE_Bounds,
		advance:      LE_Advance,
	}

	LE_Kern_Pair :: struct {
		left, right: u32le,
		advance:     LE_Advance,
	}

	LE_Variant_Header :: struct {
		flags:            Font_Flags,
		weight:           u32le,
		codepoint_type:   Codepoint_Type,
		image_type:       Image_Type,
		fallback_variant: u32le,
		fallback_glyph:   u32le,
		__reserved:       [6]u32le `fmt:"-"`,
		metrics:          LE_Metrics,
		name_length:      u32le,
		metadata_length:  u32le,
		glyph_count:      u32le,
		kern_pair_count:  u32le,
	}

	LE_Image_Header :: struct {
		flags:           u32le,
		encoding:        Image_Encoding,
		width, height:   u32le,
		channels:        u32le,
		pixel_format:    Pixel_Format,
		image_type:      Image_Type,
		row_length:      u32le,
		orientation:     i32le,
		child_images:    u32le,
		texture_flags:   u32le,
		__reserved:      [3]u32le `fmt:"-"`,
		metadata_length: u32le,
		data_length:     u32le,
	}

	LE_Appendix_Header :: struct {
		metadata_length: u32le,
		data_length:     u32le,
	}

	LE_Font_Header :: struct {
		tag:               [16]u8,
		magic_num:         u32le,
		version:           u32le,
		flags:             u32le,
		real_type:         Real_Type,
		__reserved_1:      [4]u32le `fmt:"-"`,
		metadata_format:   Metadata_Format,
		metadata_length:   u32le,
		variant_count:     u32le,
		variants_length:   u32le,
		image_count:       u32le,
		images_length:     u32le,
		appendix_count:    u32le,
		appendices_length: u32le,
		__reserved_2:      [8]u32le `fmt:"-"`,
	}

	LE_Font_Footer :: struct {
		salt:         u32le,
		magic_num:    u32le,
		__reserved_1: [4]u32le `fmt:"-"`,
		total_length: u32le,
		checksum:     u32le,
	}

	native_bounds :: proc(le: LE_Bounds) -> Bounds {
		return {cast(f32)le.left, cast(f32)le.bottom, cast(f32)le.right, cast(f32)le.top}
	}
	native_advance :: proc(le: LE_Advance) -> Advance {
		return {cast(f32)le.h, cast(f32)le.v}
	}
	native_metrics :: proc(le: LE_Metrics) -> Metrics {
		return {
			cast(f32)le.font_size,
			cast(f32)le.distance_range,
			cast(f32)le.em_size,
			cast(f32)le.ascender,
			cast(f32)le.descender,
			cast(f32)le.line_height,
			cast(f32)le.underline_y,
			cast(f32)le.underline_thickness,
			cast(f32)le.distance_range_middle,
		}
	}
	realign :: proc(r: ^bytes.Reader) {
		if (r.i & 3 > 0) {
			r.i += 4 - (r.i & 3)
		}
	}
	read :: proc(r: ^bytes.Reader, data: $S/[]$T) -> (err: Error) {
		data_bytes := slice.reinterpret([]byte, data)

		n := bytes.reader_read(r, data_bytes) or_return
		assert(n == len(data_bytes))
		return nil
	}
	read_struct :: proc(r: ^bytes.Reader, v: ^$T) -> (err: Error) {
		bytes := (cast([^]byte)v)[:size_of(T)]
		defer if err != nil {
			v^ = {}
		}
		return read(r, bytes)
	}
	read_string :: proc(r: ^bytes.Reader, length: int) -> (str: string, err: Error) {
		bytes := make([]byte, length)
		defer if err != nil {
			delete(bytes)
		}
		read(r, bytes) or_return
		str = cast(string)bytes
		realign(r)
		return
	}

	context.allocator = allocator

	reader: bytes.Reader
	bytes.reader_init(&reader, data)

	prev_length: i64

	header: LE_Font_Header
	read_struct(&reader, &header) or_return

	if string(header.tag[:]) != HEADER_TAG {
		return {}, .Not_An_Artery_File
	}
	if header.magic_num != HEADER_MAGIC_NUM {
		return {}, .Invalid_Magic
	}
	if header.version != HEADER_VERSION {
		return {}, .Invalid_Version
	}

	font.metadata_format = header.metadata_format
	font.metadata = read_string(&reader, cast(int)header.metadata_length) or_return

	prev_length = reader.i

	variants := make([dynamic]Font_Variant, 0, header.variant_count)
	defer if err != nil {
		for variant in variants {
			delete(variant.metadata)
			delete(variant.glyphs)
			delete(variant.kern_pairs)
		}
		delete(variants)
	}

	glyphs := make([dynamic]LE_Glyph, context.temp_allocator)
	defer delete(glyphs)
	kern_pairs := make([dynamic]LE_Kern_Pair, context.temp_allocator)
	defer delete(kern_pairs)

	for _ in 0 ..< header.variant_count {
		variant: Font_Variant

		variant_header: LE_Variant_Header
		read_struct(&reader, &variant_header) or_return

		variant.flags = variant_header.flags
		variant.weight = cast(u32)variant_header.weight
		variant.codepoint_type = variant_header.codepoint_type
		variant.image_type = variant_header.image_type
		variant.fallback_variant = cast(u32)variant_header.fallback_variant
		variant.fallback_glyph = cast(u32)variant_header.fallback_glyph
		variant.metrics = native_metrics(variant_header.metrics)

		switch variant.image_type {
		case .Linear_Mask, .Sdf, .Msdf, .Mtsdf:
		// Ok
		case .None, .Srgb_Image, .Masked_Srgb_Image, .Psdf, .Mixed_Content:
			return {}, .Unsupported_Image_Type
		}

		name_bytes := make([]byte, variant_header.name_length)
		defer if err != nil {
			delete(name_bytes)
		}
		read(&reader, name_bytes) or_return
		variant.name = cast(string)name_bytes

		meta_bytes := make([]byte, variant_header.metadata_length)
		defer if err != nil {
			delete(meta_bytes)
		}
		read(&reader, meta_bytes) or_return
		variant.metadata = cast(string)meta_bytes

		resize(&glyphs, variant_header.glyph_count)
		read(&reader, glyphs[:]) or_return

		resize(&kern_pairs, variant_header.kern_pair_count)
		read(&reader, kern_pairs[:][:]) or_return

		variant.glyphs = make([]Glyph, len(glyphs))
		defer if err != nil {
			delete(variant.glyphs)
		}
		for glyph, i in glyphs {
			variant.glyphs[i] = {
				codepoint    = cast(u32)glyph.codepoint,
				image        = cast(u32)glyph.image,
				plane_bounds = native_bounds(glyph.plane_bounds),
				image_bounds = native_bounds(glyph.image_bounds),
				advance      = native_advance(glyph.advance),
			}
			if glyph.image != 0 {
				// TODO: Support multiple images (3D sampler?)
				return {}, .Multiple_Images_Unsupported
			}
		}

		variant.kern_pairs = make([]Kern_Pair, len(kern_pairs))
		for pair, i in kern_pairs {
			variant.kern_pairs[i] = {
				left    = cast(u32)pair.left,
				right   = cast(u32)pair.right,
				advance = native_advance(pair.advance),
			}
		}

		append(&variants, variant)
	}
	if reader.i - prev_length != cast(i64)header.variants_length {
		return
	}

	prev_length = reader.i
	font.variants = variants[:]

	images := make([dynamic]Image, 0, header.image_count)
	defer if err != nil {
		for image in images {
			delete(image.metadata)
			delete(image.data)
		}
		delete(images)
	}

	image_data := make([dynamic]byte, context.temp_allocator)
	defer delete(image_data)

	for _ in 0 ..< header.image_count {
		font_image: Image

		image_header: LE_Image_Header
		read_struct(&reader, &image_header) or_return

		font_image.encoding = image_header.encoding
		font_image.width = cast(u32)image_header.width
		font_image.height = cast(u32)image_header.height
		font_image.channels = cast(u32)image_header.channels
		font_image.pixel_format = image_header.pixel_format
		font_image.image_type = image_header.image_type
		font_image.child_images = cast(u32)image_header.child_images

		if font_image.pixel_format != .Unsigned8 {
			return {}, .Unsupported_Pixel_Format
		}

		meta_bytes := make([]byte, image_header.metadata_length)
		defer if err != nil {
			delete(meta_bytes)
		}
		read(&reader, meta_bytes) or_return
		font_image.metadata = cast(string)meta_bytes

		resize(&image_data, image_header.data_length)
		read(&reader, image_data[:]) or_return

		opts: png.Options
		switch font_image.channels {
		case 1, 4: // We good
		case 3:
			opts += {.alpha_add_if_missing}
		case:
			return {}, .Unsupported_Pixel_Format
		}

		switch font_image.encoding {
		case .Unknown_Encoding:
			return {}, .Unknown_Encoding
		case .Raw_Binary:
			if font_image.channels == 3 {
				font_image.channels = 4
				font_image.data = make(
					[]byte,
					font_image.width * font_image.height * font_image.channels,
				)
				for i := 0; i < len(font_image.data); i += 4 {
					font_image.data[i + 0] = image_data[0]
					font_image.data[i + 1] = image_data[1]
					font_image.data[i + 2] = image_data[2]
					font_image.data[i + 3] = 255
				}
			} else {
				font_image.data = slice.clone(image_data[:])
			}
		case .Tiff:
			unimplemented()
		case .Bmp, .Png, .Tga:
			img := image.load(image_data[:], opts, context.temp_allocator) or_return
			defer image.destroy(img, context.temp_allocator)
			font_image.channels = 4
			font_image.data = slice.clone(img.pixels.buf[:])
		}

		append(&images, font_image)
		realign(&reader)
	}
	if reader.i - prev_length != cast(i64)header.images_length {
		return
	}

	prev_length = reader.i
	font.images = images[:]

	appendices := make([dynamic]Appendix, 0, header.appendix_count)
	defer if err != nil {
		for appendix in appendices {
			delete(appendix.metadata)
			delete(appendix.data)
		}
		delete(appendices)
	}

	for _ in 0 ..< header.appendix_count {
		appendix: Appendix

		appendix_header: LE_Appendix_Header
		read_struct(&reader, &appendix_header) or_return

		meta_bytes := make([]byte, appendix_header.metadata_length)
		defer if err != nil {
			delete(meta_bytes)
		}
		read(&reader, meta_bytes) or_return
		appendix.metadata = cast(string)meta_bytes

		appendix_data := make([]byte, appendix_header.data_length)
		defer if err != nil {
			delete(appendix_data)
		}
		read(&reader, appendix_data) or_return

		appendix.data = appendix_data
		realign(&reader)
	}
	if reader.i - prev_length != cast(i64)header.appendix_count {
		return
	}

	prev_length = reader.i
	font.appendices = appendices[:]

	footer: LE_Font_Footer
	read_struct(&reader, &footer) or_return

	if footer.magic_num != FOOTER_MAGIC_NUM {
		return {}, .Invalid_Magic
	}

	checksum := crc32(data[:len(data) - size_of(footer.checksum)])

	if checksum != cast(u32)footer.checksum {
		return {}, .Invalid_Checksum
	}
	if reader.i != cast(i64)footer.total_length {
		return {}, .Data_Left_Over
	}

	return
}

load_font :: proc {
	load_font_from_path,
	load_font_from_memory,
}

// Custom crc32 because the format doesn't actually use the normal one
@(private = "file")
crc32 :: proc(data: []byte) -> u32 {
	// odinfmt:disable
	@(static)
	table := [256]u32{
		0x00000000, 0x77073096, 0xee0e612c, 0x990951ba, 0x076dc419, 0x706af48f, 0xe963a535, 0x9e6495a3,
		0x0edb8832, 0x79dcb8a4, 0xe0d5e91e, 0x97d2d988, 0x09b64c2b, 0x7eb17cbd, 0xe7b82d07, 0x90bf1d91,
		0x1db71064, 0x6ab020f2, 0xf3b97148, 0x84be41de, 0x1adad47d, 0x6ddde4eb, 0xf4d4b551, 0x83d385c7,
		0x136c9856, 0x646ba8c0, 0xfd62f97a, 0x8a65c9ec, 0x14015c4f, 0x63066cd9, 0xfa0f3d63, 0x8d080df5,
		0x3b6e20c8, 0x4c69105e, 0xd56041e4, 0xa2677172, 0x3c03e4d1, 0x4b04d447, 0xd20d85fd, 0xa50ab56b,
		0x35b5a8fa, 0x42b2986c, 0xdbbbc9d6, 0xacbcf940, 0x32d86ce3, 0x45df5c75, 0xdcd60dcf, 0xabd13d59,
		0x26d930ac, 0x51de003a, 0xc8d75180, 0xbfd06116, 0x21b4f4b5, 0x56b3c423, 0xcfba9599, 0xb8bda50f,
		0x2802b89e, 0x5f058808, 0xc60cd9b2, 0xb10be924, 0x2f6f7c87, 0x58684c11, 0xc1611dab, 0xb6662d3d,
		0x76dc4190, 0x01db7106, 0x98d220bc, 0xefd5102a, 0x71b18589, 0x06b6b51f, 0x9fbfe4a5, 0xe8b8d433,
		0x7807c9a2, 0x0f00f934, 0x9609a88e, 0xe10e9818, 0x7f6a0dbb, 0x086d3d2d, 0x91646c97, 0xe6635c01,
		0x6b6b51f4, 0x1c6c6162, 0x856530d8, 0xf262004e, 0x6c0695ed, 0x1b01a57b, 0x8208f4c1, 0xf50fc457,
		0x65b0d9c6, 0x12b7e950, 0x8bbeb8ea, 0xfcb9887c, 0x62dd1ddf, 0x15da2d49, 0x8cd37cf3, 0xfbd44c65,
		0x4db26158, 0x3ab551ce, 0xa3bc0074, 0xd4bb30e2, 0x4adfa541, 0x3dd895d7, 0xa4d1c46d, 0xd3d6f4fb,
		0x4369e96a, 0x346ed9fc, 0xad678846, 0xda60b8d0, 0x44042d73, 0x33031de5, 0xaa0a4c5f, 0xdd0d7cc9,
		0x5005713c, 0x270241aa, 0xbe0b1010, 0xc90c2086, 0x5768b525, 0x206f85b3, 0xb966d409, 0xce61e49f,
		0x5edef90e, 0x29d9c998, 0xb0d09822, 0xc7d7a8b4, 0x59b33d17, 0x2eb40d81, 0xb7bd5c3b, 0xc0ba6cad,
		0xedb88320, 0x9abfb3b6, 0x03b6e20c, 0x74b1d29a, 0xead54739, 0x9dd277af, 0x04db2615, 0x73dc1683,
		0xe3630b12, 0x94643b84, 0x0d6d6a3e, 0x7a6a5aa8, 0xe40ecf0b, 0x9309ff9d, 0x0a00ae27, 0x7d079eb1,
		0xf00f9344, 0x8708a3d2, 0x1e01f268, 0x6906c2fe, 0xf762575d, 0x806567cb, 0x196c3671, 0x6e6b06e7,
		0xfed41b76, 0x89d32be0, 0x10da7a5a, 0x67dd4acc, 0xf9b9df6f, 0x8ebeeff9, 0x17b7be43, 0x60b08ed5,
		0xd6d6a3e8, 0xa1d1937e, 0x38d8c2c4, 0x4fdff252, 0xd1bb67f1, 0xa6bc5767, 0x3fb506dd, 0x48b2364b,
		0xd80d2bda, 0xaf0a1b4c, 0x36034af6, 0x41047a60, 0xdf60efc3, 0xa867df55, 0x316e8eef, 0x4669be79,
		0xcb61b38c, 0xbc66831a, 0x256fd2a0, 0x5268e236, 0xcc0c7795, 0xbb0b4703, 0x220216b9, 0x5505262f,
		0xc5ba3bbe, 0xb2bd0b28, 0x2bb45a92, 0x5cb36a04, 0xc2d7ffa7, 0xb5d0cf31, 0x2cd99e8b, 0x5bdeae1d,
		0x9b64c2b0, 0xec63f226, 0x756aa39c, 0x026d930a, 0x9c0906a9, 0xeb0e363f, 0x72076785, 0x05005713,
		0x95bf4a82, 0xe2b87a14, 0x7bb12bae, 0x0cb61b38, 0x92d28e9b, 0xe5d5be0d, 0x7cdcefb7, 0x0bdbdf21,
		0x86d3d2d4, 0xf1d4e242, 0x68ddb3f8, 0x1fda836e, 0x81be16cd, 0xf6b9265b, 0x6fb077e1, 0x18b74777,
		0x88085ae6, 0xff0f6a70, 0x66063bca, 0x11010b5c, 0x8f659eff, 0xf862ae69, 0x616bffd3, 0x166ccf45,
		0xa00ae278, 0xd70dd2ee, 0x4e048354, 0x3903b3c2, 0xa7672661, 0xd06016f7, 0x4969474d, 0x3e6e77db,
		0xaed16a4a, 0xd9d65adc, 0x40df0b66, 0x37d83bf0, 0xa9bcae53, 0xdebb9ec5, 0x47b2cf7f, 0x30b5ffe9,
		0xbdbdf21c, 0xcabac28a, 0x53b39330, 0x24b4a3a6, 0xbad03605, 0xcdd70693, 0x54de5729, 0x23d967bf,
		0xb3667a2e, 0xc4614ab8, 0x5d681b02, 0x2a6f2b94, 0xb40bbe37, 0xc30c8ea1, 0x5a05df1b, 0x2d02ef8d,
	}
	// odinfmt:enable

	c := ~u32(0)
	for b in data {
		c = table[u8(c ~ u32(b))] ~ (c >> 8)
	}
	return c
}
