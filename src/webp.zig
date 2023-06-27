const std = @import("std");
const webp = @cImport({
    @cInclude("webp/decode.h");
});
pub const Decoder = webp.WebPIDecoder;
pub const DecoderOptions = webp.WebPDecoderConfig;
pub const DecoderBuffer = webp.WebPDecBuffer;
pub const DecoderMode = webp.WEBP_CSP_MODE;
pub const ImageFormat = webp.WebPInputFileFormat;

extern fn WebPGetInfo(data: [*]const u8, data_size: usize, width: *usize, height: *usize) u32;
extern fn WebPDecodeRGBA(data: [*]const u8, data_size: usize, width: *usize, height: *usize) [*]u8;
extern fn WebPFree(pointer: *u8) void;

pub const ImageInfo = struct {
    width: usize = 0,
    height: usize = 0,
};

pub const ImageData = struct {
    width: usize = 0,
    height: usize = 0,
    pixels: []u8 = "",
};

pub fn getInfo(data: []const u8) ImageInfo {
    var width: usize = 0;
    var height: usize = 0;
    _ = WebPGetInfo(data.ptr, data.len, &width, &height);
    return ImageInfo{ .width = width, .height = height };
}

pub fn decodeRGBA(data: []const u8) ImageData {
    var width: usize = 0;
    var height: usize = 0;
    const pixels = WebPDecodeRGBA(data.ptr, data.len, &width, &height);
    return ImageData{ .width = width, .height = height, .pixels = pixels[0 .. width * height * 4] };
}

pub fn free(pointer: []u8) void {
    WebPFree(@ptrCast(pointer.ptr));
}
