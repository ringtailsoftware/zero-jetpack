const std = @import("std");
const console = @import("console.zig").getWriter().writer();
const ziggysynth = @import("ziggysynth.zig");
const pocketmod = @cImport({
    @cInclude("pocketmod.h");
});
const Sound = @import("sound.zig");

const Game = @import("game.zig").Game;

const Vec2 = Game.Vec2;
const vec2 = Game.vec2;

const WIDTH = 800;
const HEIGHT = 800;
var gfxFramebuffer: [WIDTH * HEIGHT]u32 = undefined;

const RENDER_QUANTUM_FRAMES = 128; // WebAudio's render quantum size
var sampleRate: f32 = 44100;
var mix_left: [RENDER_QUANTUM_FRAMES]f32 = undefined;
var mix_right: [RENDER_QUANTUM_FRAMES]f32 = undefined;
var leftright: [RENDER_QUANTUM_FRAMES * 2]f32 = undefined;

var music_volume: f32 = 0.5;
var fx_volume: f32 = 1.0;

var prng = std.rand.DefaultPrng.init(0);
var rand = prng.random();

const NUMBALLS = 1000;
var balls: [NUMBALLS]Ball = undefined;

var gSurface: Game.Surface = undefined;
var gRenderer: Game.Renderer = undefined;
var gWorld: Game.World = undefined;
var zoom: f32 = 0.5;
var gSprites: Game.Sprites = undefined;
var gRock: Game.Rock = undefined;
var gBasket: Game.Basket = undefined;
var gPlayer: Game.Player = undefined;
var gEntities: Game.Entities = undefined;
var gFontBig: Game.Font = undefined;
var gFontSmall: Game.Font = undefined;
var gCurDialog: ?Game.Dialog = undefined;
var gBasketpoly: Game.Polygon = undefined;
var gCurLevel: usize = 0;
var gSmashHelpSeen: bool = false;
var gSound: Game.Sound = undefined;

var pmodctx: pocketmod.pocketmod_context = undefined;
//const mod_data = Game.Assets.ASSET_MAP.get("space_debris.mod").?;
const mod_data = @embedFile("assets/space_debris.mod");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

export fn zmalloc(size: c_int) callconv(.C) ?[*]u8 {
    //_ = console.print("zmalloc {d}\n", .{size}) catch 0;
    var mem = allocator.alloc(u8, @intCast(usize, size + @sizeOf(usize))) catch {
        _ = console.print("ALLOCFAIL", .{}) catch 0;
        return null;
    };
    const sz = @ptrCast(*usize, @alignCast(@alignOf(*usize), mem.ptr));
    sz.* = @intCast(usize, size);
    //_ = console.print("<- zmalloc ptr={any}\n", .{mem.ptr}) catch 0;
    return mem.ptr + @sizeOf(usize);
}

export fn zcalloc(count: c_int, size: c_int) callconv(.C) ?[*]u8 {
    //_ = console.print("zcalloc {d}\n", .{size}) catch 0;

    var mem: ?[*]u8 = zmalloc(count * size);
    if (mem != null) {
        @memset(mem.?[@sizeOf(usize)..@intCast(usize, size)].ptr, 0x00, @intCast(usize, count * size));
    }
    return mem;
}

export fn zfree(ptr: ?[*]u8) callconv(.C) void {
    if (ptr == null) {
        return;
    }
    //_ = console.print("zfree ptr={any}\n", .{ptr}) catch 0;

    const sz = @ptrCast(*const usize, @alignCast(@alignOf(*usize), ptr.?) - @sizeOf(usize));
    const p = ptr.? - @sizeOf(usize);
    allocator.free(p[0 .. sz.* + @sizeOf(usize)]);
}

export fn zrealloc(oldptr: ?[*]u8, size: c_int) callconv(.C) ?[*]u8 {
    if (oldptr == null) {
        return zmalloc(size);
    }
    //_ = console.print("zrealloc oldptr={any}\n", .{oldptr}) catch 0;
    const oldsz = @ptrCast(*const usize, @alignCast(@alignOf(*usize), oldptr.?) - @sizeOf(usize));
    const p = oldptr.? - @sizeOf(usize);
    var oldmem = p[0 .. oldsz.* + @sizeOf(usize)];

    //_ = console.print("oldsz {d}\n", .{oldsz}) catch 0;

    var mem = allocator.realloc(oldmem, @intCast(usize, size + @sizeOf(usize))) catch {
        _ = console.print("ALLOCFAIL", .{}) catch 0;
        return null;
    };
    const sz = @ptrCast(*usize, @alignCast(@alignOf(*usize), mem.ptr));
    sz.* = @intCast(usize, size);
    return mem.ptr + @sizeOf(usize);
}

export fn zsin(x: f64) callconv(.C) f64 {
    return @sin(x);
}
export fn zcos(x: f64) callconv(.C) f64 {
    return @cos(x);
}
export fn zsqrt(x: f64) callconv(.C) f64 {
    return std.math.sqrt(x);
}
export fn zpow(x: f64, y: f64) callconv(.C) f64 {
    return std.math.pow(f64, x, y);
}
export fn zfabs(x: f64) callconv(.C) f64 {
    return @fabs(x);
}
export fn zfloor(x: f64) callconv(.C) f64 {
    return @floor(x);
}
export fn zceil(x: f64) callconv(.C) f64 {
    return @ceil(x);
}
export fn zfmod(x: f64, y: f64) callconv(.C) f64 {
    return @mod(x, y);
}
export fn zmemcpy(dst: [*]u8, src: [*]const u8, len: c_int) [*]u8 {
    @memcpy(dst, src, @intCast(usize, len));
    return dst;
}
export fn zmemset(dst: [*]u8, val: c_int, len: c_int) [*]u8 {
    @memset(dst, @intCast(u8, val), @intCast(usize, len));
    return dst;
}

const Ball = struct {
    const Self = @This();
    pos: Vec2,
    vel: Vec2,
    sprite: *Game.Sprite,
    animationController: Game.AnimationController,

    pub fn init(pos: Vec2, vel: Vec2, sprite: *Game.Sprite) Self {
        var anim = Game.AnimationController.init();
        anim.setAction(sprite, .Spin, .ForeverRandomStart);
        return Self{
            .pos = pos,
            .vel = vel,
            .sprite = sprite,
            .animationController = anim,
        };
    }

    pub fn step(self: *Self) void {
        self.pos = self.pos.add(self.vel);

        if (self.pos.x < gWorld.worldBounds.tl.x or self.pos.x > gWorld.worldBounds.br.x) {
            self.vel.x = -self.vel.x;
        }
        if (self.pos.y < gWorld.worldBounds.tl.y or self.pos.y > gWorld.worldBounds.br.y) {
            self.vel.y = -self.vel.y;
        }
    }

    pub fn render(self: *const Self, renderer: *Game.Renderer) void {
        const vp = gWorld.worldToView(self.pos);
        const s = gWorld.worldToViewScale();

        self.sprite.render(renderer, vp, vec2(16, 16).scale(s.x), self.animationController.getFrame());
    }
};

pub const std_options = struct {
    pub fn logFn(
        comptime message_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = message_level;
        _ = scope;
        _ = console.print(format ++ "\n", args) catch 0;
    }
};

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr;
    _ = trace;
    @setCold(true);
    _ = console.print("PANIC: {s}", .{msg}) catch 0;
    while (true) {}
}

export fn keyevent(keycode: u32, down: bool) void {
    if (down) {
        Game.keystate.press(keycode);
    } else {
        Game.keystate.release(keycode);
    }
}

export fn getGfxBufPtr() [*]u8 {
    return @ptrCast([*]u8, &gfxFramebuffer);
}

export fn setSampleRate(s: f32) void {
    sampleRate = s;
    _ = pocketmod.pocketmod_init(&pmodctx, mod_data, mod_data.len, @floatToInt(c_int, sampleRate));

    gSound = Game.Sound.init(sampleRate, "assets/gzdoom.sf2");
}

export fn getLeftBufPtr() [*]u8 {
    return @ptrCast([*]u8, &mix_left);
}

export fn getRightBufPtr() [*]u8 {
    return @ptrCast([*]u8, &mix_right);
}

export fn renderSoundQuantum() void {
    var bytes: usize = RENDER_QUANTUM_FRAMES * 4 * 2;

    // pocketmod produces interleaved l/r/l/r data, so fetch a double batch
    var lrbuf = @ptrCast([*]u8, &leftright);
    bytes = RENDER_QUANTUM_FRAMES * 4 * 2;
    var i: usize = 0;
    while (i < bytes) {
        const count = pocketmod.pocketmod_render(&pmodctx, lrbuf + i, @intCast(c_int, bytes - i));
        i += @intCast(usize, count);
    }

    // then deinterleave it into the l and r buffers
    i = 0;
    while (i < RENDER_QUANTUM_FRAMES) : (i += 1) {
        mix_left[i] = leftright[i * 2] * music_volume;
        mix_right[i] = leftright[i * 2 + 1] * music_volume;
    }
    gSound.mixSoundQuantum(&mix_left, &mix_right, fx_volume);
}

fn randColour() u32 {
    const r8: u8 = rand.int(u8);
    const g8: u8 = rand.int(u8);
    const b8: u8 = rand.int(u8);
    return 0xFF000000 | @as(u32, b8) << 16 | @as(u32, g8) << 8 | @as(u32, r8);
}

fn resize(w: i32, h: i32) void {
    const screenRect = Game.Rect.init(0, 0, @intToFloat(f32, w), @intToFloat(f32, h));
    gWorld.setScreenViewport(screenRect, zoom);
    _ = console.print("zoom {d}\n", .{zoom}) catch 0;
}

export fn init() void {
    frameCount = 0;

    gSprites = Game.Sprites.init(allocator) catch |err| {
        _ = console.print("{any}\n", .{err}) catch 0;
        return;
    };

    Game.keystate.init();

    gWorld = Game.World.init(vec2(9999999, 9999999), vec2(WIDTH, HEIGHT));
    resize(WIDTH, HEIGHT); // recalculate view

    gSurface = Game.Surface.init(&gfxFramebuffer, 0, 0, WIDTH, HEIGHT, WIDTH);
    gRenderer = Game.Renderer.init(&gSurface);

    gFontBig = Game.Font.init("FiraSans-Regular.ttf", 32) catch |err| {
        _ = console.print("err {any}\n", .{err}) catch 0;
        return;
    };

    gFontSmall = Game.Font.init("SourceCodePro-Regular.ttf", 24) catch |err| {
        _ = console.print("err {any}\n", .{err}) catch 0;
        return;
    };

    var coins: [7]*Game.Sprite = .{
        gSprites.get("goldcoin").?,
        gSprites.get("redcoin").?,
        gSprites.get("silvercoin").?,
        gSprites.get("greengem").?,
        gSprites.get("yellowgem").?,
        gSprites.get("redgem").?,
        gSprites.get("azuregem").?,
    };

    for (&balls) |*ball| {
        ball.* = Ball.init(vec2(rand.float(f32) * @as(f32, WIDTH * 2) - WIDTH, rand.float(f32) * @as(f32, HEIGHT * 2) - HEIGHT), // pos
            vec2(rand.float(f32) * 4 - 2, rand.float(f32) * 4 - 2), // direction
            coins[rand.int(usize) % coins.len]);
    }

    Game.initTime(); // zero millis() clock

    setupLevel(gCurLevel);
}

fn setupLevel(level: usize) void {
    var buf: [16]u8 = undefined;
    var fname_png = std.fmt.bufPrint(&buf, "level{d}.png", .{level}) catch |err| {
        _ = console.print("err {any}\n", .{err}) catch 0;
        unreachable;
    };

    const data = Game.Assets.ASSET_MAP.get(fname_png);

    var fname_txt = std.fmt.bufPrint(&buf, "level{d}.txt", .{level}) catch |err| {
        _ = console.print("err {any}\n", .{err}) catch 0;
        unreachable;
    };

    const txt = Game.Assets.ASSET_MAP.get(fname_txt);

    if (data == null or txt == null) { // no such file, game over
        gCurDialog = Game.Dialog.init(Game.endGameText, &gFontBig, gSprites.get("portrait-frog").?, true);
    } else {
        const levelData = Game.Level.load(data.?, txt.?) catch |err| {
            _ = console.print("err {any}\n", .{err}) catch 0;
            unreachable;
        };

        const pv = [_]Vec2{
            vec2(-1, -0.30970149253731355),
            vec2(-1, 0.30970149253731355),
            vec2(1, 0.30970149253731355),
            vec2(1, -0.30970149253731355),
            vec2(0.6492537313432838, -0.30970149253731355),
            vec2(0.6169154228855727, -0.21268656716417908),
            vec2(0.5074626865671645, -0.043532338308457375),
            vec2(0.35074626865671643, 0.08582089552238813),
            vec2(0.16417910447761197, 0.16293532338308453),
            vec2(0.06467661691542292, 0.18283582089552258),
            vec2(-0.0024875621890544375, 0.18781094527363176),
            vec2(-0.13432835820895517, 0.1753731343283582),
            vec2(-0.26119402985074613, 0.1380597014925373),
            vec2(-0.37810945273631835, 0.07338308457711454),
            vec2(-0.4303482587064674, 0.03109452736318441),
            vec2(-0.5049751243781093, -0.0385572139303482),
            vec2(-0.6144278606965174, -0.21268656716417908),
            vec2(-0.6517412935323383, -0.30970149253731355),
        };

        var polycomps = [1]Game.PolygonComponent{
            Game.PolygonComponent{
                .negative = false,
                .verts = &pv,
            },
        };

        gBasketpoly = Game.Polygon.init(allocator, &polycomps, levelData.basketScale, levelData.basketPos) catch |err| {
            _ = console.print("err {any}\n", .{err}) catch 0;
            return;
        };
        gBasket = Game.Basket.init(gBasketpoly);

        const rockBitmapWidth: usize = levelData.width;
        const rockBitmapHeight: usize = levelData.height;
        const rockScale: f32 = levelData.rockScale;
        const rockBitmap = levelData.rockBitmap;

        var rockpoly = Game.Polygon.initFromBitmap(allocator, rockBitmapWidth, rockBitmapHeight, rockBitmap, rockScale) catch |err| {
            _ = console.print("err {any}\n", .{err}) catch 0;
            return;
        };
        gRock = Game.Rock.init(rockpoly, gSprites.get("rock").?);

        gPlayer = Game.Player.init(gSprites.get("zero").?);
        gPlayer.body.pos = levelData.startPos;
        gWorld.trackWorldWindow(gPlayer.body.pos);

        gEntities = Game.Entities.init(allocator, &gSprites);

        for (levelData.eggInfos) |eggInfo| {
            _ = gEntities.addEgg(gSprites.get("egg").?, eggInfo.pos, true, eggInfo.sizeMultiplier) catch |err| {
                _ = console.print("err {any}\n", .{err}) catch 0;
                return;
            };
        }

        gCurDialog = Game.Dialog.init(levelData.text, &gFontBig, gSprites.get("portrait-frog").?, false);
    }
}

export fn update(deltaMs: u32) void {
    if (gCurDialog != null) {
        gCurDialog.?.update(deltaMs, &gSound);
        if (gCurDialog.?.finished()) {
            gCurDialog.?.deinit();
            gCurDialog = null;
        }
    } else {
        if (Game.keystate.isDown(Game.Key.ZoomIn) and zoom < 4) {
            zoom *= 1.05;
            resize(WIDTH, HEIGHT);
        }
        if (Game.keystate.isDown(Game.Key.ZoomOut) and zoom > 0.2) {
            zoom *= 0.95;
            resize(WIDTH, HEIGHT);
        }
        if (Game.keystate.isDown(Game.Key.Act)) {
            _ = console.print("pos {d},{d}\n", .{ gPlayer.body.pos.x, gPlayer.body.pos.y }) catch 0;
        }

        for (&balls) |*ball| {
            ball.step();
        }

        gEntities.update(&gWorld, deltaMs, &gRock, &gPlayer, &gBasket, &gSound) catch |err| {
            _ = console.print("err {any}\n", .{err}) catch 0;
            return;
        };

        const towMass = gEntities.countEggMassUnderTow();

        gPlayer.update(&gWorld, deltaMs, &gRock, &gBasket, towMass, &gSound);
        gWorld.trackWorldWindow(gPlayer.body.pos);

        if (gEntities.countEggsSmashed() != 0) {
            if (!gSmashHelpSeen) {
                gCurDialog = Game.Dialog.init(Game.smashHelpText, &gFontBig, gSprites.get("portrait-frog").?, false);
                gSmashHelpSeen = true;
            }
        }

        if (gEntities.countEggsRemaining() == 0) {
            gCurLevel += 1;
            setupLevel(gCurLevel);
        }
    }
}

var lastTime: u32 = 0;
var lastFPSTime: u32 = 0;
var frameCount: usize = 0;
var lastFPS: u32 = 0;

fn showFPS() void {
    if (Game.millis() > lastFPSTime + 1000) {
        lastFPS = frameCount / ((Game.millis() - lastFPSTime) / 1000);
        //_ = console.print("FPS {d}\n", .{lastFPS}) catch 0;
        //_ = console.print("Stats: {any}\n", .{gRenderer.stats}) catch 0;
        gRenderer.stats.reset();
        lastFPSTime = Game.millis();
        frameCount = 0;
    }
    frameCount +%= 1;
    lastTime = Game.millis();

    var buf: [16]u8 = undefined;
    var sl = std.fmt.bufPrint(&buf, "{d} fps", .{lastFPS}) catch |err| {
        _ = console.print("err {any}\n", .{err}) catch 0;
        return;
    };
    gRenderer.drawString(&gFontSmall, sl, 0, 24, 0xFFFFFFFF);
}

export fn renderGfx() void {
    gRenderer.fill(0xFF000000); // black background

    gWorld.render(&gRenderer);

    for (&balls) |*ball| {
        ball.step();
        ball.render(&gRenderer);
    }

    gRock.render(&gRenderer, &gWorld);
    gBasket.render(&gRenderer, &gWorld);
    gPlayer.render(&gRenderer, &gWorld);

    gEntities.render(&gRenderer, &gWorld, &gPlayer);

    if (gCurDialog != null) {
        gCurDialog.?.render(&gRenderer);
    }

    showFPS();
}
