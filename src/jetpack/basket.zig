const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

pub const Basket = struct {
    const Self = @This();
    poly: Game.Polygon,
    pos: Vec2,
    scale: f32,

    pub fn init(poly: Game.Polygon) Self {
        return Self{
            .poly = poly,
            .pos = vec2(0, 0),
            .scale = 1.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.poly.deinit();
    }

    pub fn render(self: *const Self, renderer: *Game.Renderer, world: *Game.World) void {
        self.poly.render(renderer, world, self.pos, self.scale);
    }

    pub fn collideCircle(self: *const Self, pos: Vec2, radius: f32) ?[2]Vec2 {
        return self.poly.collideCircle(pos, radius);
    }
};
