const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const STOPPED_SPEED = 10;

pub const Player = struct {
    const Self = @This();
    body: Game.Body,
    animController: Game.AnimationController,
    sprite: *Game.Sprite,
    lastBobPos: Vec2,
    bobPos: Vec2, // relative to body.pos
    angle: f32,

    pub fn init(sprite: *Game.Sprite) Self {
        // zig fmt: off
        var s = Self{
            .body = Game.Body.init(vec2(0,0), 64, 1),
            .sprite = sprite,
            .animController = Game.AnimationController.init(),
            .bobPos = vec2(0,0),
            .lastBobPos = vec2(0,0),
            .angle = 0,
        };
        // zig fmt: on

        s.bobPos = s.body.pos.add(vec2(0, 150));
        s.lastBobPos = s.bobPos;

        s.animController.setAction(s.sprite, Game.AnimationAction.FlyLeft, Game.AnimationController.LoopStyle.Forever);
        return s;
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    fn updateBob(self: *Self, world: *Game.World, deltaMs: i64) void {
        if (deltaMs > 1000) {
            std.log.info("**BOBFRAMETOOLONG", .{});
            return;
        }

        // scale factor deltaMs to give constant speed regardless of fps
        const deltaScale = @intToFloat(f32, deltaMs) / 1000.0;

        // update point
        const delta = (self.bobPos.sub(self.lastBobPos)).scale(0.95); // however far it moved last frame, with drag
        self.lastBobPos = self.bobPos;
        self.bobPos = self.bobPos.add(delta); // move it same again
        self.bobPos.y += 50 * deltaScale; //(world.gravity) * deltaScale;
        _ = world;

        // constrain line
        const p1 = self.body.pos;
        const p2 = self.bobPos;
        // get the distance between the points
        const distance = p2.sub(p1).length();
        // get the fractional distance the points need to move toward or away from center of
        // line to make line length correct
        const length = self.body.radius;
        const fraction = ((length - distance) / distance) / 2; // divide by 2 as each point moves half the distance to
        // correct the line length
        const move = p2.sub(p1).scale(fraction);
        self.bobPos = self.bobPos.add(move);

        self.angle = std.math.atan2(f32, self.body.pos.y - self.bobPos.y, self.body.pos.x - self.bobPos.x) + std.math.pi / 2.0;
    }

    pub fn update(self: *Self, world: *Game.World, deltaMs: i64, rock: *const Game.Rock, basket: *const Game.Basket, towMass: f32, sound: *Game.Sound) void {
        var imp = vec2(0, 0);
        if (Game.keystate.isDown(Game.Key.Left)) {
            sound.singleShot(.ThrustOn);
            imp = imp.add(vec2(-1, 0));
        }
        if (Game.keystate.isDown(Game.Key.Right)) {
            sound.singleShot(.ThrustOn);
            imp = imp.add(vec2(1, 0));
        }
        if (Game.keystate.isDown(Game.Key.Up)) {
            sound.singleShot(.ThrustOn);
            imp = imp.add(vec2(0, -1));
        }
        if (Game.keystate.isDown(Game.Key.Down)) {
            sound.singleShot(.ThrustOn);
            imp = imp.add(vec2(0, 1));
        }

        if (imp.x == 0 and imp.y == 0) {
            sound.singleShot(.ThrustOff);
        }

        self.body.applyImpulse(imp.scale(world.gravity * 2));
        self.body.update(world, deltaMs, rock, basket, towMass);

        self.updateBob(world, deltaMs);

        const dir = self.body.vel.normalize();

        //        if (std.math.fabs(dir.x) > std.math.fabs(dir.y)) {
        if (self.body.thrust.length() > 0.1) {
            if (dir.x > 0) {
                self.animController.setAction(self.sprite, Game.AnimationAction.ThrustRight, Game.AnimationController.LoopStyle.Forever);
            } else {
                self.animController.setAction(self.sprite, Game.AnimationAction.ThrustLeft, Game.AnimationController.LoopStyle.Forever);
            }
        } else {
            if (dir.x > 0) {
                self.animController.setAction(self.sprite, Game.AnimationAction.FlyRight, Game.AnimationController.LoopStyle.Forever);
            } else {
                self.animController.setAction(self.sprite, Game.AnimationAction.FlyLeft, Game.AnimationController.LoopStyle.Forever);
            }
        }
        //        } else {
        //            if (dir.y > 0) {
        //                self.animController.setAction(self.sprite, Game.AnimationAction.FlyDown, Game.AnimationController.LoopStyle.Forever);
        //            } else {
        //                self.animController.setAction(self.sprite, Game.AnimationAction.FlyUp, Game.AnimationController.LoopStyle.Forever);
        //            }
        //        }
    }

    pub fn render(self: *Self, renderer: *Game.Renderer, world: *Game.World) void {
        const posv = world.worldToView(self.body.pos);
        const s = world.worldToViewScale();
        var r = self.body.radius * std.math.min(s.x, s.y); // worldWindow might be different aspect, fudge it

        self.body.render(renderer, world);

        //        const angle = self.body.thrust.normalize().x * (std.math.pi / 6.0);
        // FIXME rotated sprites
        //self.sprite.render(renderer, posv, vec2(r * 2, r * 2), self.animController.getFrame());
        self.sprite.renderRotated(renderer, posv, vec2(r * 2, r * 2), self.animController.getFrame(), self.angle);

        // bob
        if (false) {
            const bobv = world.worldToView(self.bobPos);
            renderer.drawLine(@floatToInt(i16, posv.x), @floatToInt(i16, posv.y), @floatToInt(i16, bobv.x), @floatToInt(i16, bobv.y), 0xFF00FF00);
        }
    }

    pub fn getLanding(self: *const Self) ?Vec2 {
        _ = self;
        // perhaps landing is when pos no longer moving and pos is close to a recent contact pt
        //return self.landingPos;
        return null;
    }
};
