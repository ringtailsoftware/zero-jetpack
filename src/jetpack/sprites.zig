const std = @import("std");

const zigimg = @import("zigimg");
const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const Allocator = std.mem.Allocator;

const SpriteSheetCoord = [2]u16; // coords on sprite sheet
pub const AnimationFrame = [2]u32; // texture index, delayms

pub const AnimationAction = enum {
    Idle,
    WalkDown,
    WalkLeft,
    WalkRight,
    WalkUp,
    //    MineRight,
    //    MineLeft,
    //    MineUp,
    //    MineDown,
    Death,
    Spin,
    Move,
    Hurt,
    Attack,
    FlyLeft,
    FlyRight,
    ThrustLeft,
    ThrustRight,
};

const JsonSpriteAnimation = struct {
    idle: ?[]AnimationFrame = null,
    walkdown: ?[]AnimationFrame = null,
    walkleft: ?[]AnimationFrame = null,
    walkright: ?[]AnimationFrame = null,
    walkup: ?[]AnimationFrame = null,
    //    mineright: ?[]AnimationFrame = null,
    //    mineleft: ?[]AnimationFrame = null,
    //    mineup: ?[]AnimationFrame = null,
    //    minedown: ?[]AnimationFrame = null,
    death: ?[]AnimationFrame = null,
    spin: ?[]AnimationFrame = null,
    move: ?[]AnimationFrame = null,
    hurt: ?[]AnimationFrame = null,
    attack: ?[]AnimationFrame = null,
    flyleft: ?[]AnimationFrame = null,
    flyright: ?[]AnimationFrame = null,
    thrustleft: ?[]AnimationFrame = null,
    thrustright: ?[]AnimationFrame = null,
};

const JsonSprite = struct {
    const Self = @This();
    name: []u8,
    filename: []u8,
    size: SpriteSheetCoord,
    textures: []SpriteSheetCoord,
    animations: []JsonSpriteAnimation,
};

pub const Sprite = struct {
    const Self = @This();
    size: SpriteSheetCoord,
    textures: []SpriteSheetCoord,
    animations: []JsonSpriteAnimation,
    animActions: std.enums.EnumMap(AnimationAction, []AnimationFrame),
    sheetSurf: *Game.Surface,
    name: []u8,

    pub fn create(allocator: Allocator, size: SpriteSheetCoord, textures: []SpriteSheetCoord, animations: []JsonSpriteAnimation, animActions: std.enums.EnumMap(AnimationAction, []AnimationFrame), sheetSurf: *Game.Surface, name: []const u8) !*Self {
        var s = allocator.create(Self) catch |err| {
            return err;
        };
        s.textures = textures;
        s.animations = animations;
        s.animActions = animActions;
        s.sheetSurf = sheetSurf;
        s.size = size;
        s.name = try allocator.dupe(u8, name);
        return s;
    }

    pub fn getAnim(self: *const Self, action: AnimationAction) ?[]AnimationFrame {
        return self.animActions.get(action);
    }

    pub fn render(self: *const Self, renderer: *Game.Renderer, pos: Vec2, dim: Vec2, frameIndex: u32) void {
        const sheetSurf = self.sheetSurf;
        const srcx = self.textures[frameIndex][0];
        const srcy = self.textures[frameIndex][1];
        const srcw = self.size[0];
        const srch = self.size[1];

        var spriteSurf = Game.Surface.init(sheetSurf.oc.pixels, srcx, srcy, srcw, srch, sheetSurf.width);

        const dstx = Game.compat_floatToInt(i32, pos.x - dim.x / 2);
        const dsty = Game.compat_floatToInt(i32, pos.y - dim.y / 2);

        renderer.sprite_blend(&spriteSurf, dstx, dsty, Game.compat_floatToInt(i32, dim.x), Game.compat_floatToInt(i32, dim.y));
    }

    pub fn renderRotated(self: *const Self, renderer: *Game.Renderer, pos: Vec2, dim: Vec2, frameIndex: u32, angleRad: f32) void {
        const sheetSurf = self.sheetSurf;
        const srcx = self.textures[frameIndex][0];
        const srcy = self.textures[frameIndex][1];
        const srcw = self.size[0];
        const srch = self.size[1];

        var spriteSurf = Game.Surface.init(sheetSurf.oc.pixels, srcx, srcy, srcw, srch, sheetSurf.width);

        const dstx = Game.compat_floatToInt(i32, pos.x - dim.x / 2);
        const dsty = Game.compat_floatToInt(i32, pos.y - dim.y / 2);

        renderer.sprite_blend_rotated(&spriteSurf, dstx, dsty, Game.compat_floatToInt(i32, dim.x), Game.compat_floatToInt(i32, dim.y), angleRad);
    }
};

const JsonSpritesTop = struct { items: []JsonSprite };

pub const Sprites = struct {
    const Self = @This();
    parsedData: JsonSpritesTop,
    spriteMap: std.StringHashMap(*Sprite),
    textureMap: std.StringHashMap(*Game.Surface),

    pub fn init(allocator: Allocator) !Self {
        const spritesJson = Game.Assets.ASSET_MAP.get("sprites.json").?;

        //var stream = std.json.TokenStream.init(spritesJson);

        var spriteMap = std.StringHashMap(*Sprite).init(std.heap.page_allocator);
        var textureMap = std.StringHashMap(*Game.Surface).init(std.heap.page_allocator);

        //const parsedData = std.json.parse(JsonSpritesTop, &stream, .{ .allocator = allocator, .ignore_unknown_fields = true });
        const parsedData = std.json.parseFromSlice(JsonSpritesTop, allocator, spritesJson, .{ .ignore_unknown_fields = true });
        if (parsedData) |j| {
            const jsprites = j.value;
            var animActions: std.enums.EnumMap(AnimationAction, []AnimationFrame) = .{};
            for (jsprites.items) |*jsprite| {
                //std.log.info("Sprite name={s} filename={s} size={},{} textures={any}", .{sprite.name, sprite.filename, sprite.size[0], sprite.size[1], sprite.textures});
                // fixup animActions
                for (jsprite.*.animations) |anim| {
                    if (anim.idle != null) animActions.put(AnimationAction.Idle, anim.idle.?);
                    if (anim.walkdown != null) animActions.put(AnimationAction.WalkDown, anim.walkdown.?);
                    if (anim.walkleft != null) animActions.put(AnimationAction.WalkLeft, anim.walkleft.?);
                    if (anim.walkright != null) animActions.put(AnimationAction.WalkRight, anim.walkright.?);
                    if (anim.walkup != null) animActions.put(AnimationAction.WalkUp, anim.walkup.?);
                    //                    if (anim.mineleft != null) animActions.put(AnimationAction.MineLeft, anim.mineleft.?);
                    //                    if (anim.mineright != null) animActions.put(AnimationAction.MineRight, anim.mineright.?);
                    //                    if (anim.minedown != null) animActions.put(AnimationAction.MineDown, anim.minedown.?);
                    //                    if (anim.mineup != null) animActions.put(AnimationAction.MineUp, anim.mineup.?);
                    if (anim.death != null) animActions.put(AnimationAction.Death, anim.death.?);
                    if (anim.spin != null) animActions.put(AnimationAction.Spin, anim.spin.?);
                    if (anim.move != null) animActions.put(AnimationAction.Move, anim.move.?);
                    if (anim.hurt != null) animActions.put(AnimationAction.Hurt, anim.hurt.?);
                    if (anim.attack != null) animActions.put(AnimationAction.Attack, anim.attack.?);
                    if (anim.flyleft != null) animActions.put(AnimationAction.FlyLeft, anim.flyleft.?);
                    if (anim.flyright != null) animActions.put(AnimationAction.FlyRight, anim.flyright.?);
                    if (anim.thrustleft != null) animActions.put(AnimationAction.ThrustLeft, anim.thrustleft.?);
                    if (anim.thrustright != null) animActions.put(AnimationAction.ThrustRight, anim.thrustright.?);
                }

                if (!textureMap.contains(jsprite.*.filename)) {
                    //std.log.err("load tex {s}", .{jsprite.*.filename});
                    const data = Game.Assets.ASSET_MAP.get(jsprite.*.filename).?;
                    const im: zigimg.Image = zigimg.Image.fromMemory(std.heap.page_allocator, data) catch |err| {
                        return err;
                    };
                    // im is allocated, sheetSurf is copied and just has a pointer to allocated buf
                    //const sl = std.mem.bytesAsSlice(u32, @as(*u32, @alignCast(im.pixels.asBytes())));
                    //const sl = std.mem.bytesAsSlice(u32, @as([]u32, @alignCast(im.pixels.asBytes())));
                    const p = im.pixels.asBytes().ptr;
                    const sheetSurf: *Game.Surface = Game.Surface.create(allocator, @alignCast(@ptrCast(p)), 0, 0, im.width, im.height, im.width) catch |err| {
                        //                    const sheetSurf: *Game.Surface = Game.Surface.create(allocator, sl.ptr, 0, 0, im.width, im.height, im.width) catch |err| {
                        return err;
                    };
                    try textureMap.put(jsprite.*.filename, sheetSurf);
                }

                // get the sheetSurface
                const sheetSurf = textureMap.get(jsprite.*.filename).?;
                // save sprite in map

                // needs to be allocated!
                const sprite: *Sprite = Sprite.create(std.heap.page_allocator, jsprite.*.size, jsprite.*.textures, jsprite.*.animations, animActions, sheetSurf, jsprite.*.name) catch |err| {
                    return err;
                };
                try spriteMap.put(jsprite.name, sprite);
            }
            return Self{
                .parsedData = jsprites,
                .spriteMap = spriteMap,
                .textureMap = textureMap,
            };
        } else |err| {
            std.log.info("JSON err {}", .{err});
            return err;
        }
    }

    pub fn get(self: *const Self, name: []const u8) ?*Sprite {
        return self.spriteMap.get(name);
    }

    pub fn deinit(self: Self) void {
        _ = self;
        // FIXME
        //        std.json.parseFree(JsonSpritesTop, self.parsedData);
        //        self.spriteMap.deinit();
    }
};
