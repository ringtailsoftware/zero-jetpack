const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const RndGen = std.rand.DefaultPrng;
var prng = std.rand.DefaultPrng.init(0);
var rand = prng.random();

const EGG_SIZE = 32;
const TOW_LEN = 150;
const SMASH_SPEED = 200;

const EggState = enum {
    Init,
    Idle,
    UnderTowAttach,
    UnderTow,
    Smashed,
    InBasket,
    Finished,
};

pub const Egg = struct {
    const Self = @This();
    body: Game.Body,
    animController: Game.AnimationController,
    sprite: *Game.Sprite,
    state: EggState,
    lastBobPos: Vec2,
    lastBobSpeed: f32,
    lastBobVel: Vec2,
    angle:f32,
    angleVel:f32,
    startPos:Vec2,
    autorespawn:bool,
    sizeMultiplier:f32,

    pub fn init(sprite:*Game.Sprite, pos:Vec2, autorespawn:bool, sizeMultiplier:f32) Self {
        // zig fmt: off
        var s = Self{
            .autorespawn = autorespawn,
            .startPos = pos,
            .body = Game.Body.init(pos, EGG_SIZE + EGG_SIZE * sizeMultiplier, 0.5 + 0.5 * sizeMultiplier),
            .sprite = sprite,
            .animController = Game.AnimationController.init(),
            .state = EggState.Init,
            .lastBobPos = vec2(0,0),
            .lastBobVel = vec2(0,0),
            .angle = 0,
            .angleVel = 0,
            .lastBobSpeed = 0,
            .sizeMultiplier = sizeMultiplier,
        };
        // zig fmt: on
        s.body.bounceElasticity = 0.2;
        s.lastBobPos = s.body.pos;
        s.animController.setAction(s.sprite, Game.AnimationAction.Spin, Game.AnimationController.LoopStyle.ForeverRandomStart);
        return s;
    }

    fn updateBob(self: *Self, world: *Game.World, player: *const Game.Player, deltaMs:i64) void {
        if (deltaMs > 1000) {
            std.log.info("**EGGBOBFRAMETOOLONG", .{});
            return;
        }

        // scale factor deltaMs to give constant speed regardless of fps
        const deltaScale = @intToFloat(f32, deltaMs) / 1000.0;

        // update point
        const delta = (self.body.pos.sub(self.lastBobPos)).scale(0.99);    // however far it moved last frame, with drag
        self.lastBobSpeed = delta.length() * (1/deltaScale);
        self.lastBobVel = delta.scale(1/deltaScale);
        self.lastBobPos = self.body.pos;
        self.body.pos = self.body.pos.add(delta);   // move it same again
        self.body.pos.y += 10 * deltaScale;//(world.gravity) * deltaScale;
_ = world;

        // constrain line
        const p1 = player.body.pos;
        const p2 = self.body.pos;
        // get the distance between the points
        const distance = p2.sub(p1).length();
        // get the fractional distance the points need to move toward or away from center of
        // line to make line length correct
        var length:f32 = TOW_LEN;
        // allow length to shorten if player is nearer
        const toPlayer = player.body.pos.sub(self.body.pos);
        const distToPlayer = toPlayer.length();
        if (distToPlayer < length) {
            length  = distToPlayer;
        }

        const fraction = ((length - distance) / distance) / 2;  // divide by 2 as each point moves half the distance to
                                                               // correct the line length
        const move = p2.sub(p1).scale(fraction);
        self.body.pos = self.body.pos.add(move);

        const prevAngle = self.angle;
        self.angle = std.math.atan2(f32, player.body.pos.y - self.body.pos.y, player.body.pos.x - self.body.pos.x) + std.math.pi/2.0;
        self.angleVel = (self.angle - prevAngle) / deltaScale;
    }

    pub fn update(self: *Self, entities:*Game.Entities, id:Game.EntityId, world: *Game.World, deltaMs: i64, rock: *const Game.Rock, player: *Game.Player, basket: *Game.Basket, sound:*Game.Sound) !void {
        var runphys = true;

        // scale factor deltaMs to give constant speed regardless of fps
        const deltaScale = @intToFloat(f32, deltaMs) / 1000.0;

        const toPlayer = player.body.pos.sub(self.body.pos);
        const distToPlayer = toPlayer.length();

        switch(self.state) {
            .Init => {
                // push away in some random direction
                //self.body.applyImpulse(vec2(rand.float(f32)*2 - 1 , rand.float(f32)*2 - 1).normalize().scale(world.gravity));
                self.state = .Idle;
            },
            .Idle => {
                if (distToPlayer <= player.body.radius + self.body.radius) {
                    self.state = .UnderTowAttach;
                }
            },
            .UnderTowAttach => {
                if (distToPlayer >= TOW_LEN) {
                    self.lastBobPos = self.body.pos;
                    self.state = .UnderTow;
                }
            },
            .UnderTow => {
                const oldPos = self.body.pos;   // hack, should be stopping updateBob changing it directly
                self.updateBob(world, player, deltaMs);
                runphys = false;
                if (rock.collideCircle(self.body.pos, self.body.radius)) |inter| {
                    // hit rock
                    self.body.pos = oldPos;
                    _ = inter;
                    std.log.info("HIT VEL={d}", .{self.lastBobSpeed});
                    if (self.lastBobSpeed > SMASH_SPEED) {
                        sound.singleShot(.Smashed);
                        self.state = .Smashed;
                        self.body.vel = self.lastBobVel;
                        self.animController.setAction(self.sprite, Game.AnimationAction.Death, Game.AnimationController.LoopStyle.Single);
                    }
                }
                if (basket.collideCircle(self.body.pos, self.body.radius)) |inter| {
                    // hit basket
                    self.body.pos = oldPos;
                    _ = inter;
                    std.log.info("HIT VEL={d}", .{self.lastBobSpeed});
                    if (self.lastBobSpeed > SMASH_SPEED) {
                        sound.singleShot(.Smashed);
                        self.state = .Smashed;
                        self.body.vel = self.lastBobVel;
                        self.animController.setAction(self.sprite, Game.AnimationAction.Death, Game.AnimationController.LoopStyle.Single);
                    } else {
                        std.log.info("BASKET LANDING", .{});
                        sound.singleShot(.InBasket);
                        self.state = .InBasket;
                        self.body.vel = vec2(0,0);
                    }
                }

                if (distToPlayer > TOW_LEN * 1.5) { // over-stretched
                    sound.singleShot(.Smashed);
                    self.state = .Smashed;
                    self.body.vel = self.lastBobVel;
                    self.animController.setAction(self.sprite, Game.AnimationAction.Death, Game.AnimationController.LoopStyle.Single);
                }
            },
            .Smashed => {
                // wait for animation to complete
                self.angle += self.angleVel * deltaScale;    // no longer attached, spin at last angular vel
                self.angleVel *= 0.98;  // not framerate independent, but slow it down
                if (self.animController.finished()) {
                    try entities.remove(id);    // safe as doesn't remove us immediately
                    if (self.autorespawn) {
                        _ = try entities.addEgg(self.sprite, self.startPos, true, self.sizeMultiplier);
                    }
                }
            },
            .InBasket => {
                _ = try entities.addFloater(self.body.pos, "goldcoin");
                self.state = .Finished;
            },
            .Finished => {
            },
        }

        if (runphys) {
            self.body.update(world, deltaMs, rock, basket, 0);
        }
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn render(self: *Self, renderer: *Game.Renderer, world: *Game.World, player: *const Game.Player) void {
        const posv = world.worldToView(self.body.pos);
        const s = world.worldToViewScale();
        var r = self.body.radius * std.math.min(s.x, s.y); // worldWindow might be different aspect, fudge it

        if (self.state == .UnderTow or self.state == .UnderTowAttach) {
            const playerv = world.worldToView(player.body.pos);
            renderer.drawLine(@floatToInt(i32, posv.x), @floatToInt(i32, posv.y), @floatToInt(i32, playerv.x), @floatToInt(i32, playerv.y), 0xFFFFFF00);
        }

        self.body.render(renderer, world);
        self.sprite.renderRotated(renderer, posv, vec2(r * 2, r * 2), self.animController.getFrame(), self.angle);
    }
};
