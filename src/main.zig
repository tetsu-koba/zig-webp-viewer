const std = @import("std");
const log = std.log;
const webp = @import("webp.zig");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
});

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

    // Create window in temporary size
    var window = sdl.SDL_CreateWindow("WebP Display", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, 1, 1, sdl.SDL_WINDOW_RESIZABLE);
    if (window == null) {
        log.err("Window could not be created! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyWindow(window);

    // Get screen size
    const display_index = sdl.SDL_GetWindowDisplayIndex(window);
    var rect: sdl.SDL_Rect = undefined;
    if (sdl.SDL_GetDisplayUsableBounds(display_index, &rect) != 0) {
        log.err("SDL could get display usable bounds! SDL_Error: {s}", .{sdl.SDL_GetError()});
        return;
    }

    const screen_width = @intCast(usize, rect.w);
    const screen_height = @intCast(usize, rect.h);

    const image = webp.decodeRGBA(image_data);
    defer webp.free(image.pixels);

    const w0 = if (screen_width < image.width) screen_width else image.width;
    const h0 = if (screen_height < image.height) screen_height else image.height;
    var window_width = @intCast(c_int, @intCast(u64, h0) * @intCast(u64, image.width) / @intCast(u64, image.height));
    var window_height = @intCast(c_int, @intCast(u64, w0) * @intCast(u64, image.height) / @intCast(u64, image.width));
    if (window_width > w0) {
        window_width = @intCast(c_int, w0);
    } else {
        window_height = @intCast(c_int, h0);
    }
    sdl.SDL_SetWindowSize(window, window_width, window_height);
    sdl.SDL_SetWindowPosition(window, @divTrunc(@intCast(c_int, screen_width) - window_width, 2), @divTrunc(@intCast(c_int, screen_height) - window_height, 2));

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

    _ = sdl.SDL_RenderClear(renderer);
    _ = sdl.SDL_RenderCopy(renderer, texture, null, &sdl.SDL_Rect{ .x = 0, .y = 0, .w = window_width, .h = window_height });
    sdl.SDL_RenderPresent(renderer);

    var quit = false;
    while (!quit) {
        var resized = false;
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_WaitEventTimeout(&event, 100) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    quit = true;
                    break;
                },
                sdl.SDL_WINDOWEVENT => {
                    if (event.window.event == sdl.SDL_WINDOWEVENT_RESIZED) {
                        resized = true;
                        log.info("resize: width={d}, height={d}", .{ event.window.data1, event.window.data2 });
                        window_width = event.window.data1;
                        window_height = event.window.data2;
                    }
                },
                sdl.SDL_KEYUP => {
                    switch (event.key.keysym.sym) {
                        sdl.SDLK_SPACE => {},
                        sdl.SDLK_q => {
                            quit = true;
                            break;
                        },
                        else => {},
                    }
                },
                else => {},
            }
        }
        if (resized) {
            var render_width = @intCast(c_int, @intCast(u64, window_height) * @intCast(u64, image.width) / @intCast(u64, image.height));
            var render_height = @intCast(c_int, @intCast(u64, window_width) * @intCast(u64, image.height) / @intCast(u64, image.width));
            if (render_width > window_width) {
                render_width = window_width;
            } else {
                render_height = window_height;
            }
            var render_quad = sdl.SDL_Rect{
                .x = @divTrunc(window_width - render_width, 2),
                .y = @divTrunc(window_height - render_height, 2),
                .w = render_width,
                .h = render_height,
            };
            _ = sdl.SDL_RenderClear(renderer);
            _ = sdl.SDL_RenderCopy(renderer, texture, null, &render_quad);
            sdl.SDL_RenderPresent(renderer);
        }
    }
}
