const std = @import("std");
const zigimg = @import("zigimg");
const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

pub const endGameText: [3][]const u8 = .{ "All levels complete!", "Game over", "Reload to play again" };
pub const smashHelpText: [3][]const u8 = .{ "I said be careful!", "", "" };

var txtLines: [3][]const u8 = undefined;

pub const EggInfo = struct {
    pos: Vec2,
    sizeMultiplier: f32,
};

pub const Level = struct {
    const Self = @This();
    text: [3][]const u8,
    width: usize,
    height: usize,
    rockBitmap: []const u8,
    rockScale: f32,
    eggInfos: []const EggInfo,
    basketPos: Vec2,
    basketScale: f32,
    startPos: Vec2,

    pub fn load(data: []const u8, text: []const u8) !Self {
        const im: zigimg.Image = zigimg.Image.fromMemory(std.heap.page_allocator, data) catch |err| {
            return err;
        };
        std.log.err("size={d},{d}", .{ im.width, im.height });

        var s: Self = undefined;

        // split incoming text into 3 lines to display in dialog
        var splits = std.mem.splitAny(u8, text, "\n");
        var n: usize = 0;
        while (splits.next()) |line| {
            std.log.err("line {d} = {s}", .{ n, line });
            if (n < 3) {
                txtLines[n] = line;
            }
            n += 1;
        }

        s.text = txtLines;
        s.width = im.width;
        s.height = im.height;
        s.rockScale = 200;
        s.basketScale = 100; // basket poly is 2units wide, so half scale of rocks
        var rockBitmap = std.heap.page_allocator.alloc(u8, im.width * im.height) catch |err| {
            std.log.err("err={any}", .{err});
            return err;
        };

        var eggs = std.ArrayList(EggInfo).initCapacity(std.heap.page_allocator, 1) catch |err| {
            std.log.err("err={any}", .{err});
            return err;
        };

        // world is centred at 0,0. Pixels will need offsetting
        const sz = vec2(Game.compat_intToFloat(f32, im.width) * s.rockScale, Game.compat_intToFloat(f32, im.height) * s.rockScale);

        var it = im.iterator();
        var i: usize = 0;
        while (it.next()) |pix| {
            const x: usize = @rem(i, im.width);
            const y: usize = @divFloor(i, im.width);

            // black is wall
            if (pix.r == 0 and pix.g == 0 and pix.b == 0) {
                rockBitmap[i] = 1;
            } else {
                rockBitmap[i] = 0;
            }
            // red is egg
            if (pix.r != 0 and pix.g == 0 and pix.b == 0) {
                var szm: f32 = 0.0;
                if (pix.r == 1) {
                    szm = 1.0;
                } else if (pix.r >= 0.5) {
                    szm = 0.5;
                }

                std.log.err("{d} {d}", .{ szm, pix.r });
                eggs.append(EggInfo{
                    .pos = vec2((Game.compat_intToFloat(f32, x) + 0.5) * s.rockScale, (Game.compat_intToFloat(f32, y) + 0.5) * s.rockScale).sub(sz.scale(0.5)),
                    .sizeMultiplier = szm,
                }) catch |err| {
                    std.log.err("err={any}", .{err});
                    unreachable;
                };
            }
            // blue is player start
            if (pix.b != 0 and pix.r == 0 and pix.g == 0) {
                s.startPos = vec2((Game.compat_intToFloat(f32, x) + 0.5) * s.rockScale, (Game.compat_intToFloat(f32, y) + 0.5) * s.rockScale).sub(sz.scale(0.5));
            }
            // green is basket
            if (pix.g != 0 and pix.r == 0 and pix.b == 0) {
                s.basketPos = vec2((Game.compat_intToFloat(f32, x) + 0.5) * s.rockScale, (Game.compat_intToFloat(f32, y) + 0.5) * s.rockScale).sub(sz.scale(0.5));
            }
            i += 1;
        }

        s.rockBitmap = rockBitmap;
        s.eggInfos = eggs.items;
        return s;
    }
};
