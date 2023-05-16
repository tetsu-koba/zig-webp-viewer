# WebP Image Viewer written in Zig

Actually this is my practice to use libsdl2 and libwebp in Zig

## Dependency

You need to install libsdl2 and libwebp developer package.
On the Debian/Ubuntu:

```
$ sudo apt install -y libwebp-dev libsdl2-dev
```

On Mac with HomeBrew

```
% brew update
% brew install webp sdl2
```

## Build

```
% zig version
0.11.0-dev.3132+465272921
% zig build
```

## Usage

```
% zig-out/bin/webp-viewer 
Usage: zig-out/bin/webp-viewer image.webp...
```

You can specify multiple fies.

## Key operation

SPACE, RIGHT, DOWN, RETURN: show the next image.
LEFT, UP: show the previous image.
q: quit.

