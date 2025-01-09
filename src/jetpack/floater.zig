const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const RndGen = std.Random.DefaultPrng;
var prng = std.Random.DefaultPrng.init(0);
var rand = prng.random();

const FLOATER_SIZE = 32;

const FloaterState = enum { Init, Running };

pub const Floater = struct {
    const Self = @This();
    body: Game.Body,
    animController: Game.AnimationController,
    sprite: *Game.Sprite,
    state: FloaterState,

    pub fn init(sprite: *Game.Sprite, pos: Vec2) Self {
        // zig fmt: off
        var s = Self{
            .body = Game.Body.init(pos, FLOATER_SIZE, 1),
            .sprite = sprite,
            .animController = Game.AnimationController.init(),
            .state = FloaterState.Init,
        };
        // zig fmt: on

        s.animController.setAction(s.sprite, Game.AnimationAction.Spin, Game.AnimationController.LoopStyle.ForeverRandomStart);
        return s;
    }

    pub fn update(self: *Self, entities: *Game.Entities, id: Game.EntityId, world: *Game.World, deltaMs: i64, rock: *const Game.Rock, player: *Game.Player, basket: *Game.Basket) !void {
        switch (self.state) {
            .Init => {
                // push away in some random direction, always up
                self.body.applyImpulse(vec2(rand.float(f32) * 2 - 1, -1).normalize().scale(world.gravity * 4));
                self.state = .Running;
            },
            .Running => {
                if (self.body.age > 500) { // let them spread out first
                    const toPlayer = player.body.pos.sub(self.body.pos);
                    const dirToPlayer = toPlayer.normalize();
                    const distToPlayer = toPlayer.length();
                    if (distToPlayer < player.body.radius * 4) {
                        self.body.applyImpulse(dirToPlayer.scale(world.gravity * 8)); // magnet direction chasing
                    }

                    if (distToPlayer < player.body.radius) {
                        try entities.remove(id);
                    }
                }
            },
        }

        self.body.update(world, deltaMs, rock, basket, 0);
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn render(self: *Self, renderer: *Game.Renderer, world: *Game.World) void {
        const posv = world.worldToView(self.body.pos);
        const s = world.worldToViewScale();
        const r = self.body.radius * @min(s.x, s.y); // worldWindow might be different aspect, fudge it

        self.body.render(renderer, world);
        self.sprite.render(renderer, posv, vec2(r * 2, r * 2), self.animController.getFrame());
    }
};
