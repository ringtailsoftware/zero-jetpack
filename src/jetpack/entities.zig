const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

pub const EntityId = usize;

pub const Entity = union(enum) {
    floater: Game.Floater,
    egg: Game.Egg,
};

pub const Entities = struct {
    const Self = @This();
    entities: std.AutoArrayHashMap(EntityId, Entity),
    toRemove: std.ArrayList(EntityId),
    sprites: *Game.Sprites,
    curId: EntityId,

    fn getNextId(self: *Self) EntityId {
        const curId = self.curId;
        self.curId += 1;
        return curId;
    }

    pub fn init(allocator: std.mem.Allocator, sprites: *Game.Sprites) Self {
        return Self{
            .sprites = sprites,
            .entities = std.AutoArrayHashMap(EntityId, Entity).init(allocator),
            .toRemove = std.ArrayList(EntityId).init(allocator),
            .curId = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        // destroy every item
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .floater => |*floater| {
                    floater.deinit();
                },
                .egg => |*egg| {
                    egg.deinit();
                },
            }
        }
        self.entities.deinit();
        self.toRemove.deinit();
    }

    pub fn addFloater(self: *Self, pos: Vec2, spriteName: []const u8) !EntityId {
        const f = Game.Floater.init(self.sprites.get(spriteName).?, pos);
        const id = self.getNextId();
        try self.entities.put(id, Entity{ .floater = f });
        return id;
    }

    pub fn addEgg(self: *Self, sprite: *Game.Sprite, pos: Vec2, autorespawn: bool, sizeMultiplier: f32) !EntityId {
        const e = Game.Egg.init(sprite, pos, autorespawn, sizeMultiplier);
        const id = self.getNextId();
        try self.entities.put(id, Entity{ .egg = e });
        return id;
    }

    pub fn remove(self: *Self, id: EntityId) !void {
        // add to remove later list
        try self.toRemove.append(id);
    }

    pub fn update(self: *Self, world: *Game.World, deltaMs: i64, rock: *const Game.Rock, player: *Game.Player, basket: *Game.Basket, sound: *Game.Sound) !void {
        // remove any pending in toRemove
        while (self.toRemove.popOrNull()) |id| {
            var entity = self.entities.get(id).?;
            // deinit the entity
            switch (entity) {
                .floater => |*floater| {
                    floater.deinit();
                },
                .egg => |*egg| {
                    egg.deinit();
                },
            }
            // remove from entities map
            _ = self.entities.orderedRemove(id);
        }
        // update all remaining
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .floater => |*floater| {
                    try floater.update(self, entity.key_ptr.*, world, deltaMs, rock, player, basket);
                },
                .egg => |*egg| {
                    try egg.update(self, entity.key_ptr.*, world, deltaMs, rock, player, basket, sound);
                },
            }
        }
    }

    pub fn countFloaters(self: *const Self) usize {
        var count: usize = 0;
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .floater => count += 1,
                else => {},
            }
        }
        return count;
    }

    pub fn countEggsRemaining(self: *const Self) usize {
        var count: usize = 0;
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .egg => |*egg| {
                    if (egg.state != .Finished) {
                        count += 1;
                    }
                },
                else => {},
            }
        }
        return count;
    }

    pub fn countEggsSmashed(self: *const Self) usize {
        var count: usize = 0;
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .egg => |*egg| {
                    if (egg.state == .Smashed) {
                        count += 1;
                    }
                },
                else => {},
            }
        }
        return count;
    }

    pub fn countEggMassUnderTow(self: *const Self) f32 {
        var mass: f32 = 0;
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .egg => |*egg| {
                    if (egg.state == .UnderTow) {
                        mass += egg.body.mass;
                    }
                },
                else => {},
            }
        }
        return mass;
    }

    pub fn render(self: *Self, renderer: *Game.Renderer, world: *Game.World, player: *const Game.Player) void {
        var it = self.entities.iterator();
        while (it.next()) |entity| {
            switch (entity.value_ptr.*) {
                .floater => |*floater| {
                    floater.render(renderer, world);
                },
                .egg => |*egg| {
                    egg.render(renderer, world, player);
                },
            }
        }
    }
};
