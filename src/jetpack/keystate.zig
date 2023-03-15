const std = @import("std");

// JavaScript KeyCode values
pub const Scancode = enum(u8) {
    left = 37,
    right = 39,
    up = 38,
    down = 40,
    q = 81,
    space = 32,
    equals = 61, // firefox
    equals2 = 187,
    minus = 173, // firefox
    minus2 = 189,
    escape = 27,
};

pub const Key = enum {
    Left,
    Right,
    Up,
    Down,
    Act,
    ZoomIn,
    ZoomOut,
    Quit,
};

var pressedKeys: std.enums.EnumSet(Key) = .{};

pub fn init() void {}

fn scancodeToKey(scancode: u32) ?Key {
    return switch (scancode) {
        @enumToInt(Scancode.left) => Key.Left,
        @enumToInt(Scancode.right) => Key.Right,
        @enumToInt(Scancode.up) => Key.Up,
        @enumToInt(Scancode.down) => Key.Down,
        @enumToInt(Scancode.space) => Key.Act,
        @enumToInt(Scancode.equals), @enumToInt(Scancode.equals2) => Key.ZoomIn,
        @enumToInt(Scancode.minus), @enumToInt(Scancode.minus2) => Key.ZoomOut,
        @enumToInt(Scancode.escape), @enumToInt(Scancode.q) => Key.Quit,
        else => null,
    };
}

pub fn press(scancode: u32) void {
    if (scancodeToKey(scancode)) |key| {
        pressedKeys.insert(key);
    }
}

pub fn release(scancode: u32) void {
    if (scancodeToKey(scancode)) |key| {
        pressedKeys.remove(key);
    }
}

pub fn isDown(key: Key) bool {
    return pressedKeys.contains(key);
}

pub fn anyDown() bool {
    return pressedKeys.count() > 0;
}
