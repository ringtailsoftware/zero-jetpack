const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

pub const Body = struct {
    const Self = @This();
    pos: Vec2,
    vel: Vec2,
    thrust: Vec2,
    radius: f32,
    friction: f32,
    thrustDecay: f32,
    maxSpeed: f32,
    bounceElasticity: f32,
    contactPt: ?Vec2,
    contactNorm: ?Vec2,
    impulse: ?Vec2,
    impulseTime: i64,
    age: i64,
    mass: f32,

    pub fn init(pos: Vec2, radius: f32, mass: f32) Self {
        // zig fmt: off
        var s = Self{
            .pos = pos,
            .vel = vec2(0, 0),
            .thrust = vec2(0, 0),
            .radius = radius,
            .thrustDecay = 0.1,
            .friction = 1.0,
            .maxSpeed = 750,
            .bounceElasticity = 0.5,
            .contactPt = null,
            .contactNorm = null,
            .impulse = null,
            .impulseTime = 0,
            .age = 0,
            .mass = mass,
        };
        // zig fmt: on
        return s;
    }

    pub fn applyImpulse(self: *Self, impulse: Vec2) void {
        self.impulse = impulse;
        self.impulseTime = self.age;
    }

    pub fn update(self: *Self, world: *Game.World, deltaMs: i64, rock: *const Game.Rock, basket: *const Game.Basket, extraMass: f32) void {
        if (deltaMs > 1000) {
            std.log.info("**FRAMETOOLONG", .{});
            return;
        }

        // scale factor deltaMs to give constant speed regardless of fps
        const deltaScale = @intToFloat(f32, deltaMs) / 1000.0;

        const speed = self.vel.length();

        // decay thrust
        //        self.thrust = self.thrust.scale(std.math.pow(f32, self.thrustDecay, deltaScale));

        if (self.impulse != null) {
            const thr = self.impulse.?;
            self.thrust = thr;
            //            self.thrust = self.thrust.add(thr);
            if (self.age > self.impulseTime + 250) {
                self.impulse = null;
            }
        } else {
            self.thrust = vec2(0, 0);
        }

        // apply thrust
        self.vel = self.vel.add(self.thrust.scale(deltaScale));

        // apply gravity
        const g = vec2(0, world.gravity * (self.mass + extraMass)).scale(deltaScale);
        self.vel = self.vel.add(g);

        // decay vel
        self.vel = self.vel.scale(std.math.pow(f32, self.friction, deltaScale));

        // clip vel
        if (speed > self.maxSpeed) {
            self.vel = self.vel.normalize().scale(self.maxSpeed);
        }

        // vel is in units/s, scale by update delta for constant rate regardless of fps
        const newpos = self.pos.add(self.vel.scale(deltaScale));

        var aabb = Rect{ .tl = vec2(newpos.x - self.radius, newpos.y - self.radius), .br = vec2(newpos.x + self.radius, newpos.y + self.radius) };

        // is new aabb entirely inside world bounds?
        if (world.worldBounds.containsRect(aabb)) {
            if (basket.collideCircle(newpos, self.radius) orelse rock.collideCircle(newpos, self.radius)) |inter| {
                // hit rock, bounce
                self.contactPt = inter[0];
                self.contactNorm = inter[1];
                // https://math.stackexchange.com/questions/13261/how-to-get-a-reflection-vector
                const bounceVel = self.contactNorm.?.scale(self.vel.dot(self.contactNorm.?)).scale(2);
                self.vel = self.vel.sub(bounceVel);
                self.vel = self.vel.scale(self.bounceElasticity);
            } else {
                self.pos = newpos;
                self.contactPt = null;
                self.contactNorm = null;
            }
        } else {
            self.vel = vec2(0, 0); // absorb energy, no bounce
            self.thrust = vec2(0, 0);
        }

        self.age += deltaMs;
    }

    pub fn render(self: *Self, renderer: *Game.Renderer, world: *Game.World) void {
        if (false) {
            const posv = world.worldToView(self.pos);
            const s = world.worldToViewScale();
            var r = self.radius * std.math.min(s.x, s.y); // worldWindow might be different aspect, fudge it
            renderer.circle(@floatToInt(i32, posv.x), @floatToInt(i32, posv.y), @floatToInt(i32, r), 0xFF00FF00);
            //const thr = self.thrust.scale(s.length()/10).add(posv);
            //renderer.drawLine(@floatToInt(i32, posv.x), @floatToInt(i32, posv.y), @floatToInt(i32, thr.x), @floatToInt(i32, thr.y), 0xFF0000FF);
            const vel = self.vel.scale(s.length()).add(posv);
            renderer.drawLine(@floatToInt(i32, posv.x), @floatToInt(i32, posv.y), @floatToInt(i32, vel.x), @floatToInt(i32, vel.y), 0xFFFFFFFF);
        }
    }
};
