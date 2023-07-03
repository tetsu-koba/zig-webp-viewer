const std = @import("std");
const webp = @cImport({
    @cInclude("webp/decode.h");
});

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

    const Self = @This();

    pub fn free(self: *Self) void {
        if (self.pixels.len != 0) {
            WebPFree(@ptrCast(self.pixels.ptr));
            self.pixels = "";
            self.width = 0;
            self.height = 0;
        }
    }
};

pub fn getInfo(data: []const u8) !ImageInfo {
    var width: usize = 0;
    var height: usize = 0;
    if (WebPGetInfo(data.ptr, data.len, &width, &height) == 0) {
        return error.WebPFormatError;
    }
    return ImageInfo{ .width = width, .height = height };
}

pub fn decodeRGBA(data: []const u8) ImageData {
    var width: usize = 0;
    var height: usize = 0;
    const pixels = WebPDecodeRGBA(data.ptr, data.len, &width, &height);
    return ImageData{ .width = width, .height = height, .pixels = pixels[0 .. width * height * 4] };
}
