const std = @import("std");
const log = std.log;
const webp = @import("webp.zig");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
});

pub fn main() !void {
    const alc = std.heap.page_allocator;
    const args = try std.process.argsAlloc(alc);
    defer std.process.argsFree(alc, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} image.webp...\n", .{args[0]});
        std.posix.exit(1);
    }
    var image_viewer = try ImageViewer.init(alc, args[1..]);
    defer image_viewer.deinit();
    try image_viewer.eventLoop();
}

pub const ImageViewer = struct {
    alc: std.mem.Allocator,
    files: [][:0]u8,
    file_index: usize,
    window: ?*sdl.struct_SDL_Window,
    renderer: ?*sdl.struct_SDL_Renderer,
    surface: ?*sdl.struct_SDL_Surface,
    texture: ?*sdl.struct_SDL_Texture,
    image: webp.ImageData,
    window_width: c_int,
    window_height: c_int,
    screen_width: usize,
    screen_height: usize,

    const Self = @This();
    pub fn init(alc: std.mem.Allocator, files: [][:0]u8) !ImageViewer {
        var self: ImageViewer = .{
            .alc = alc,
            .files = files,
            .file_index = 0,
            .window = undefined,
            .renderer = null,
            .surface = null,
            .texture = null,
            .image = .{},
            .window_width = 0,
            .window_height = 0,
            .screen_width = 0,
            .screen_height = 0,
        };
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            log.err("SDL could not initialize! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }
        errdefer sdl.SDL_Quit();

        // Create window in temporary size
        self.window = sdl.SDL_CreateWindow("WebP Display", 1, 1, sdl.SDL_WINDOW_RESIZABLE);
        if (self.window == null) {
            log.err("Window could not be created! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }
        errdefer sdl.SDL_DestroyWindow(self.window);

        // Get screen size
        const display_index = sdl.SDL_GetDisplayForWindow(self.window);
        var rect: sdl.SDL_Rect = undefined;
        if (!sdl.SDL_GetDisplayUsableBounds(display_index, &rect)) {
            log.err("SDL could get display usable bounds! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }

        self.screen_width = @intCast(rect.w);
        self.screen_height = @intCast(rect.h);

        try self.loadImage();

        _ = sdl.SDL_RenderClear(self.renderer);
        _ = sdl.SDL_RenderTexture(self.renderer, self.texture, null, &sdl.SDL_FRect{ .x = 0, .y = 0, .w = @floatFromInt(self.window_width), .h = @floatFromInt(self.window_height) });
        _ = sdl.SDL_RenderPresent(self.renderer);

        return self;
    }

    pub fn deinit(self: *Self) void {
        if (self.texture != null) sdl.SDL_DestroyTexture(self.texture);
        if (self.surface != null) sdl.SDL_DestroySurface(self.surface);
        if (self.renderer != null) sdl.SDL_DestroyRenderer(self.renderer);
        self.image.free();
        if (self.window != null) sdl.SDL_DestroyWindow(self.window);
        sdl.SDL_Quit();
    }

    fn loadImage(self: *Self) !void {
        self.image.free();
        self.image = try decodeWebp(self.alc, self.files[self.file_index]);
        const image = self.image;

        const w0 = if (self.screen_width < image.width) self.screen_width else image.width;
        const h0 = if (self.screen_height < image.height) self.screen_height else image.height;
        var window_width: c_int = @intCast(@as(u64, @intCast(h0)) * @as(u64, @intCast(image.width)) / @as(u64, @intCast(image.height)));
        var window_height: c_int = @intCast(@as(u64, @intCast(w0)) * @as(u64, @intCast(image.height)) / @as(u64, @intCast(image.width)));
        if (window_width > w0) {
            window_width = @intCast(w0);
        } else {
            window_height = @intCast(h0);
        }
        self.window_width = window_width;
        self.window_height = window_height;
        _ = sdl.SDL_SetWindowSize(self.window, window_width, window_height);
        _ = sdl.SDL_SetWindowPosition(self.window, @divTrunc(@as(c_int, @intCast(self.screen_width)) - window_width, 2), @divTrunc(@as(c_int, @intCast(self.screen_height)) - window_height, 2));

        if (self.renderer != null) sdl.SDL_DestroyRenderer(self.renderer);
        self.renderer = sdl.SDL_CreateRenderer(self.window, null);
        if (self.renderer == null) {
            log.err("Renderer could not be created! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }

        if (self.surface != null) sdl.SDL_DestroySurface(self.surface);
        self.surface = sdl.SDL_CreateSurfaceFrom(@intCast(image.width), @intCast(image.height), sdl.SDL_GetPixelFormatForMasks(32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000), image.pixels.ptr, @intCast(image.width * 4));

        if (self.surface == null) {
            log.err("Unable to create surface! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }

        if (self.texture != null) sdl.SDL_DestroyTexture(self.texture);
        self.texture = sdl.SDL_CreateTextureFromSurface(self.renderer, self.surface);
        if (self.texture == null) {
            log.err("Unable to create texture from surface! SDL_Error: {s}", .{sdl.SDL_GetError()});
            return error.SDL;
        }
    }

    pub fn eventLoop(self: *Self) !void {
        var quit = false;
        while (!quit) {
            var repaint = false;
            var event: sdl.SDL_Event = undefined;
            while (sdl.SDL_WaitEventTimeout(&event, 100)) {
                switch (event.type) {
                    sdl.SDL_EVENT_QUIT => {
                        quit = true;
                        break;
                    },
                    sdl.SDL_EVENT_WINDOW_RESIZED => {
                        log.info("resize: width={d}, height={d}", .{ event.window.data1, event.window.data2 });
                        self.window_width = event.window.data1;
                        self.window_height = event.window.data2;
                        repaint = true;
                    },
                    sdl.SDL_EVENT_KEY_UP => {
                        switch (event.key.key) {
                            sdl.SDLK_SPACE, sdl.SDLK_RIGHT, sdl.SDLK_DOWN, sdl.SDLK_RETURN => {
                                if (self.file_index + 1 < self.files.len) {
                                    self.file_index += 1;
                                    try self.loadImage();
                                    repaint = true;
                                }
                            },
                            sdl.SDLK_LEFT, sdl.SDLK_UP => {
                                if (self.file_index > 0) {
                                    self.file_index -= 1;
                                    try self.loadImage();
                                    repaint = true;
                                }
                            },
                            sdl.SDLK_Q => {
                                quit = true;
                                break;
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
            if (repaint) {
                const window_width = self.window_width;
                const window_height = self.window_height;
                var render_width = @as(c_int, @intCast(@as(u64, @intCast(window_height)) * @as(u64, @intCast(self.image.width)) / @as(u64, @intCast(self.image.height))));
                var render_height = @as(c_int, @intCast(@as(u64, @intCast(window_width)) * @as(u64, @intCast(self.image.height)) / @as(u64, @intCast(self.image.width))));
                if (render_width > window_width) {
                    render_width = window_width;
                } else {
                    render_height = window_height;
                }
                var render_quad = sdl.SDL_FRect{
                    .x = @floatFromInt(@divTrunc(window_width - render_width, 2)),
                    .y = @floatFromInt(@divTrunc(window_height - render_height, 2)),
                    .w = @floatFromInt(render_width),
                    .h = @floatFromInt(render_height),
                };
                _ = sdl.SDL_RenderClear(self.renderer);
                _ = sdl.SDL_RenderTexture(self.renderer, self.texture, null, &render_quad);
                _ = sdl.SDL_RenderPresent(self.renderer);
            }
        }
    }
};

fn decodeWebp(alc: std.mem.Allocator, filename: []const u8) !webp.ImageData {
    var file0 = try std.fs.cwd().openFile(filename, .{});
    defer file0.close();
    const image_data = try file0.readToEndAlloc(alc, 4 * 1024 * 1024 * 1024);
    defer alc.free(image_data);
    return webp.decodeRGBA(image_data);
}
