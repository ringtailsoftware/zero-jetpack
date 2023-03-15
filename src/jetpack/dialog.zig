const std = @import("std");

const Game = @import("game.zig").Game;
const Vec2 = Game.Vec2;
const vec2 = Game.vec2;

const DialogState = enum {
    Opening,
    Idle,
    Closing,
    Finished,
};

const OpeningTime = 500;
const ClosingTime = 500;
const DisplayLockoutTime = 1000;

pub const Dialog = struct {
    const Self = @This();
    text: [3][]const u8,
    font: *Game.Font,
    forever: bool,
    stateStartTime: i64,
    portraitSprite: *Game.Sprite,
    animationController: Game.AnimationController,
    state: DialogState,

    pub fn init(text: [3][]const u8, font: *Game.Font, portraitSprite: *Game.Sprite, forever: bool) Self {
        var anim = Game.AnimationController.init();
        anim.setAction(portraitSprite, .Idle, .Forever);

        return Self{
            .animationController = anim,
            .text = text,
            .forever = forever,
            .stateStartTime = Game.millis(),
            .font = font,
            .portraitSprite = portraitSprite,
            .state = .Opening,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // FIXME string ownership
    }

    pub fn update(self: *Self, deltaMs: i64, sound: *Game.Sound) void {
        _ = deltaMs;

        switch (self.state) {
            .Opening => {
                if (Game.millis() > self.stateStartTime + OpeningTime) {
                    self.stateStartTime = Game.millis();
                    sound.talk(true);
                    self.state = .Idle;
                }
            },
            .Idle => {
                // ignore keypresses for a while
                if (Game.millis() > self.stateStartTime + DisplayLockoutTime) {
                    if (Game.keystate.anyDown()) { // any key
                        self.stateStartTime = Game.millis();
                        sound.talk(false);
                        self.state = .Closing;
                    }
                }
            },
            .Closing => {
                if (Game.millis() > self.stateStartTime + ClosingTime) {
                    self.state = .Finished;
                }
            },
            .Finished => {},
        }
    }

    pub fn renderPanel(self: *const Self, renderer: *Game.Renderer, tl: Vec2) void {
        const panelRect = Game.Rect.initPts(
            tl,
            tl.add(vec2(@intToFloat(f32, renderer.surface.width), 128)),
        );
        renderer.fillRect(panelRect, 0xE0202020);

        const frame = switch (self.state) {
            .Idle => self.animationController.getFrame(),
            else => 0,
        };
        self.portraitSprite.render(renderer, vec2(64, 64).add(tl), vec2(128, 128), frame);
        renderer.drawStringLines(self.font, &self.text, 128 + @floatToInt(i32, tl.x), 40 + @floatToInt(i32, tl.y), 0xFFFFFFFF);
    }

    pub fn render(self: *const Self, renderer: *Game.Renderer) void {
        var y: f32 = 0;

        switch (self.state) {
            .Opening => {
                const t = std.math.min(@intToFloat(f32, Game.millis() - self.stateStartTime) / OpeningTime, 1);
                y = Game.lerp(-128, 0, t, Game.LerpStyle.EaseInExpo);
            },
            .Idle => {
                y = 0;
            },
            .Closing, .Finished => {
                const t = std.math.min(@intToFloat(f32, Game.millis() - self.stateStartTime) / ClosingTime, 1);
                y = Game.lerp(0, -128, t, Game.LerpStyle.EaseOutExpo);
            },
        }

        self.renderPanel(renderer, vec2(0, y));
    }

    pub fn finished(self: *const Self) bool {
        return self.state == .Finished;
    }
};
