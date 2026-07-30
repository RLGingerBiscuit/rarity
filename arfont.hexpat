#pragma endian little

import std.mem;
import std.sys;

bitfield FontFlags {
    bool BOLD : 1;
    bool LIGHT : 1;
    bool EXTRA_BOLD : 1;
    bool CONDENSED : 1;
    bool ITALIC : 1;
    bool SMALL_CAPS : 1;
    padding : 3;
    bool ICONOGRAPHIC : 1;
    bool SANS_SERIF : 1;
    bool SERIF : 1;
    bool MONOSPACE : 1;
    bool CURSIVE : 1;
    padding : 18;
};

enum CodepointType : u32 {
    UNSPECIFIED = 0,
    UNICODE = 1,
    INDEXED = 2,
    ICONOGRAPHIC = 14
};

enum MetadataFormat : u32 {
    NONE = 0,
    PLAINTEXT = 1,
    JSON = 2
};

enum ImageType : u32 {
    NONE = 0,
    SRGB_IMAGE = 1,
    LINEAR_MASK = 2,
    MASKED_SRGB_IMAGE = 3,
    SDF = 4,
    PSDF = 5,
    MSDF = 6,
    MTSDF = 7,
    MIXED_CONTENT = 255
};

enum PixelFormat : u32 {
    UNKNOWN = 0,
    BOOLEAN1 = 1,
    UNSIGNED8 = 8,
    FLOAT32 = 32
};

enum ImageEncoding : u32 {
    UNKNOWN_ENCODING = 0,
    RAW_BINARY = 1,
    BMP = 4,
    TIFF = 5,
    PNG = 8,
    TGA = 9
};

enum ImageOrientation : s32 {
    TOP_DOWN = 1,
    BOTTOM_UP = -1
};

enum RealType : u32 {
    FLOAT = 0x14,
    DOUBLE = 0x18,
};

struct Metrics {
        // In pixels:
        float fontSize;
        float distanceRange;
        // Proportional to font size:
        float emSize;
        float ascender, descender;
        float lineHeight;
        float underlineY, underlineThickness;
        // In pixels:
        float distanceRangeMiddle;
        padding[92];
};

struct Bounds {
    float left, bottom, right, top;
};

struct Advance {
    float h, v;
};

struct Glyph {
    u32 codepoint;
    u32 image;
    Bounds planeBounds;
    Bounds imageBounds;
    Advance advance;
};

struct KernPair {
    u32 codepoint1, codepoint2;
    Advance advance;
};

struct FontVariantHeader {
    FontFlags flags;
    u32 weight;
    CodepointType codepointType;
    ImageType imageType;
    u32 fallbackVariant;
    u32 fallbackGlyph;
    padding[24];
    Metrics metrics;
    u32 nameLength;
    u32 metadataLength;
    u32 glyphCount;
    u32 kernPairCount;

    char name[nameLength];
    char metadata[metadataLength];
    Glyph glyphs[glyphCount];
    KernPair kernPairs[kernPairCount];
};

struct ImageHeader {
    u32 flags;
    ImageEncoding encoding;
    u32 width, height;
    u32 channels;
    PixelFormat pixelFormat;
    ImageType imageType;
    u32 rowLength;
    u32 orientation;
    u32 childImages;
    u32 textureFlags;
    padding[12];
    u32 metadataLength;
    u32 dataLength;

    char metadata[metadataLength];
    u8 data[dataLength];
    $ = std::mem::align_to(4, $);
};

struct AppendixHeader {
    u32 metadataLength;
    u32 dataLength;

    char metadata[metadataLength];
    u8 data[dataLength];
    $ = std::mem::align_to(4, $);
};

struct ArteryFontHeader {
    char tag[16];
    u32 magicNo;
    u32 version;
    u32 flags;
    RealType realType;
    padding[16];

    MetadataFormat metadataFormat;
    u32 metadataLength;
    u32 variantCount;
    u32 variantsLength;
    u32 imageCount;
    u32 imagesLength;
    u32 appendixCount;
    u32 appendicesLength;
    padding[32];

    char metadata[metadataLength];
};

struct ArteryFontFooter {
    u32 salt;
    u32 magicNo;
    padding[16];
    u32 totalLength;
    u32 checksum;
};

struct ArteryFont {
    ArteryFontHeader header;
    FontVariantHeader variant_headers[header.variantCount];
    ImageHeader image_headers[header.imageCount];
    AppendixHeader appendix_headers[header.appendixCount];
    ArteryFontFooter footer;

    std::assert($ == footer.totalLength, "did not read expected number of bytes");
};

ArteryFont font @ 0x00;
