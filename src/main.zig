const std = @import("std");
const log = std.log;
const webp = @import("webp.zig");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const SCREEN_WIDTH: c_int = 800;
pub const SCREEN_HEIGHT: c_int = 600;
pub const RESIZE_INTERVAL_MS: u32 = 100;

pub fn main() anyerror!void {
    const alc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alc);
    defer std.process.argsFree(alc, args);
    
    if (args.len < 2) {
        std.debug.print("Usage: {s} <image.webp>\n", .{args[0]});
        std.os.exit(1);
    }

    var file1 = try std.fs.cwd().openFile(args[1], .{});
    defer file1.close();
    const image_data = try file1.readToEndAlloc(alc, 4 * 1024 * 1024 * 1024);
    
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
        log.err("SDL could not initialize! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_Quit();

    const image = webp.decodeRGBA(image_data);
    defer webp.free(image.pixels);

    var window = sdl.SDL_CreateWindow("WebP Display", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH, SCREEN_HEIGHT, sdl.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        log.err("Window could not be created! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyWindow(window);

    var renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_ACCELERATED | sdl.SDL_RENDERER_PRESENTVSYNC);
    if (renderer == null) {
        log.err("Renderer could not be created! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyRenderer(renderer);

    var surface = sdl.SDL_CreateRGBSurfaceFrom(image.pixels.ptr, @intCast(c_int, image.width), @intCast(c_int, image.height), 32, @intCast(c_int, image.width * 4), 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
    
    if (surface == null) {
        log.err("Unable to create surface! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_FreeSurface(surface);

    var texture = sdl.SDL_CreateTextureFromSurface(renderer, surface);
    if (texture == null) {
        log.err("Unable to create texture from surface! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyTexture(texture);

    var quit = false;
    var resize_time: u32 = 0;
    while (!quit) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => quit = true,
                sdl.SDL_WINDOWEVENT => |windowEvent| {
                    switch (windowEvent) {
                        sdl.SDL_WINDOWEVENT_RESIZED => resize_time = sdl.SDL_GetTicks(),
                        else => {},
                    }
                },
                else => {},
            }
        }
        if (sdl.SDL_GetTicks() - resize_time > RESIZE_INTERVAL_MS) {
            var w: c_int = 0;
            var h: c_int = 0;
            sdl.SDL_GetWindowSize(window, &w, &h);
            var render_quad = sdl.SDL_Rect { .x = 0, .y = 0, .w = w, .h = h };
            _ = sdl.SDL_RenderClear(renderer);
            _ = sdl.SDL_RenderCopy(renderer, texture, null, &render_quad);
            sdl.SDL_RenderPresent(renderer);
            resize_time = 0;
        }
    }
}
