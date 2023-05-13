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

    // Get screen size
    var dm: sdl.SDL_DisplayMode = undefined;
    if (sdl.SDL_GetCurrentDisplayMode(0, &dm) != 0) {
        log.err("SDL could get display mode! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    const screen_width = @intCast(usize, dm.w);
    const screen_height = @intCast(usize, dm.h);

    const image = webp.decodeRGBA(image_data);
    defer webp.free(image.pixels);

    const w0 = if (screen_width < image.width) screen_width else image.width;
    const h0 = if (screen_height < image.height) screen_height else image.height;
    var window_width = @intCast(u64, h0) * @intCast(u64, image.width) / @intCast(u64, image.height);
    var window_height = @intCast(u64, w0) * @intCast(u64, image.height) / @intCast(u64, image.width);
    if (window_width > w0) {
        window_width = w0;
    } else {
        window_height = h0;
    }
    var window = sdl.SDL_CreateWindow("WebP Display", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @intCast(c_int, window_width), @intCast(c_int, window_height), sdl.SDL_WINDOW_RESIZABLE);
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
            var render_width = @intCast(c_int, @intCast(u64, h) * @intCast(u64, image.width) / @intCast(u64, image.height));
            var render_height = @intCast(c_int, @intCast(u64, w) * @intCast(u64, image.height) / @intCast(u64, image.width));
            if (render_width > w) {
                render_width = @intCast(c_int, w);
            } else {
                render_height = @intCast(c_int, h);
            }
            var render_quad = sdl.SDL_Rect{
                .x = @divTrunc(w - render_width, 2),
                .y = @divTrunc(h - render_height, 2),
                .w = render_width,
                .h = render_height,
            };
            _ = sdl.SDL_RenderClear(renderer);
            _ = sdl.SDL_RenderCopy(renderer, texture, null, &render_quad);
            sdl.SDL_RenderPresent(renderer);
            resize_time = 0;
        }
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}
