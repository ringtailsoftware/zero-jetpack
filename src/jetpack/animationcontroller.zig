const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const RndGen = std.rand.DefaultPrng;
var prng = std.rand.DefaultPrng.init(0);
var rand = prng.random();

pub const AnimationController = struct {
    pub const LoopStyle = enum {
        HoldFirst,
        Single,
        Forever,
        ForeverRandomStart,
    };

    const Self = @This();
    action: Game.AnimationAction,
    startTime: i64,
    sprite: *const Game.Sprite,
    loopStyle: LoopStyle,

    pub fn init() Self {
        return Self{
            .startTime = 0,
            .action = Game.AnimationAction.Idle,
            .sprite = undefined, // FIXME, expecting caller to call setAction() before render()
            .loopStyle = LoopStyle.Forever,
        };
    }

    pub fn finished(self: *const Self) bool {
        const animFrames = self.sprite.getAnim(self.action);
        if (animFrames == null) {
            return false;    // not valid, loop forever
        }
        const t = Game.millis();
        const totalDelays = getTotalDelays(animFrames.?);

        switch(self.loopStyle) {
            .Single => {
                return (t > totalDelays + self.startTime);
            },
            .HoldFirst => {
                return true;
            },
            else => {
                return false;
            },
        }
    }

    pub fn setAction(self: *Self, sprite: *const Game.Sprite, action: Game.AnimationAction, loopStyle: LoopStyle) void {
        //std.log.info("setAction {s} {}", .{ sprite.name, action });
        if (loopStyle != self.loopStyle) {
            // only update timer if changing style
            self.loopStyle = loopStyle;
            switch (loopStyle) {
                LoopStyle.ForeverRandomStart => self.startTime = rand.int(i64),
                else => self.startTime = Game.millis(),
            }
        }
        self.action = action;
        self.sprite = sprite;
    }

    fn getTotalDelays(animFrames: []Game.AnimationFrame) u32 {
        var sum: u32 = 0;
        for (animFrames) |f| {
            sum += f[1];
        }
        return sum;
    }

    pub fn getFrame(self: *const Self) u32 {
        const animFrames = self.sprite.getAnim(self.action);
        if (animFrames == null) {
            std.log.info("getFrame bad {}", .{self.action});
            return 0;
        } else {
            const t = Game.millis();
            const totalDelays = getTotalDelays(animFrames.?);
            var sumTime: u32 = 0;
            const animTime = @mod(t - self.startTime, totalDelays);
            const lastFrame = animFrames.?[animFrames.?.len - 1];

            switch (self.loopStyle) {
                LoopStyle.HoldFirst => return animFrames.?[0][0], // first frame
                LoopStyle.Single => {
                    if ((t - self.startTime) > (totalDelays - lastFrame[1])) {
                        return lastFrame[0]; // last frame
                    }
                },
                else => {},
            }

            for (animFrames.?) |f| {
                sumTime += f[1]; // delay time
                if (animTime < sumTime) {
                    return f[0]; // frame
                }
            }
            return lastFrame[0];
        }

        return 0;
    }
};
