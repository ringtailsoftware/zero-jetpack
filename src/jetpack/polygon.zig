const std = @import("std");

const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

const RndGen = std.rand.DefaultPrng;

const wobbleFactor: f32 = 0.2;

const mpe = @cImport({
    @cInclude("MPE_fastpoly2tri.h");
});

const Allocator = std.mem.Allocator;

pub const PolygonComponent = struct {
    negative: bool,
    verts: []const Vec2,
};

export fn MPE_MemorySet(buf: [*]u8, val: u8, len: u32) callconv(.C) [*]u8 {
    @memset(buf, val, len);
    return buf;
}

export fn MPE_MemoryCopy(dst: [*]u8, src: [*]u8, n: u32) callconv(.C) [*]u8 {
    @memcpy(dst, src, n);
    return dst;
}

export fn mpe_assert(func: [*:0]const u8, line: u32, a: u32) callconv(.C) void {
    if (a == 0) {
        std.log.info("MPE ASSERT FAILED {s}:{d}\n", .{ func, line });
        //        std.os.exit(1); // FIXME
    }
}

export fn mpe_debug(msg: [*:0]const u8, n: u32) callconv(.C) void {
    std.log.info("MPE DEBUG '{s}' {}\n", .{ msg, n });
}

pub const Polygon = struct {
    const Self = @This();
    polyComponents: std.ArrayList(PolygonComponent),
    triVerts: std.ArrayList(Vec2),
    triIndices: std.ArrayList([3]usize),
    aabb: Game.Rect,

    pub fn init(allocator: Allocator, polyComponents: []const PolygonComponent, scale:f32, translation:Vec2) !Self {
        var s = Self{
            .polyComponents = undefined,
            .triVerts = undefined,
            .triIndices = undefined,
            .aabb = undefined,
        };
        errdefer s.deinit();
        // FIXME, free it all after
        s.polyComponents = std.ArrayList(PolygonComponent).initCapacity(allocator, polyComponents.len) catch |err| {
            return err;
        };
        for (polyComponents) |pc| {
            var vertcopy = std.ArrayList(Vec2).initCapacity(allocator, pc.verts.len) catch |err| {
                return err;
            };
            //try vertcopy.insertSlice(0, pc.verts);
            for (pc.verts) |v| {
                try vertcopy.append(v.scale(scale).add(translation));
            }
            var newpc = PolygonComponent{
                .negative = pc.negative,
                .verts = vertcopy.items,
            };
            try s.polyComponents.append(newpc);
        }

        try s.triangulate(allocator);

        s.aabb = calcAABB(&s.triVerts);

        return s;
    }

    fn calcAABB(verts:*std.ArrayList(Vec2)) Game.Rect {
        var aabb:Game.Rect = Game.Rect{
            .tl = verts.items[0],
            .br = verts.items[0],
        };

        for (verts.items) |v| {
            if (v.x < aabb.tl.x) {
                aabb.tl.x = v.x;
            }
            if (v.x > aabb.br.x) {
                aabb.br.x = v.x;
            }
            if (v.y < aabb.tl.y) {
                aabb.tl.y = v.y;
            }
            if (v.y > aabb.br.y) {
                aabb.br.y = v.y;
            }
        }
        return aabb;
    }

    fn wobbleVec2(r: std.rand.Random, x: f32, y: f32, w: f32, off: Vec2) Vec2 {
        const xw = r.float(f32) * w;
        const yw = r.float(f32) * w;
        return vec2(x + xw, y + yw).add(off);
    }

    fn createWobbleGrid(allocator: Allocator, r: std.rand.Random, w: usize, h: usize, scale: f32, off: Vec2) !std.ArrayList(Vec2) {
        var wobbleGrid = std.ArrayList(Vec2).initCapacity(allocator, (w + 1) * (h + 1)) catch |err| {
            return err;
        };
        var y: usize = 0;
        while (y < (h + 1)) : (y += 1) {
            const fy = @intToFloat(f32, y);
            var x: usize = 0;
            while (x < (w + 1)) : (x += 1) {
                const fx = @intToFloat(f32, x);
                try wobbleGrid.append(wobbleVec2(r, fx * scale, fy * scale, wobbleFactor * scale, off));
            }
        }
        return wobbleGrid;
    }

    fn wobbleGridAt(wg: std.ArrayList(Vec2), x: usize, y: usize, w: usize) Vec2 {
        return wg.items[y * (w + 1) + x];
    }

    pub fn initFromBitmap(allocator: Allocator, width: usize, height: usize, data: []const u8, scale: f32) !Self {
        var s = Self{
            .polyComponents = undefined,
            .triVerts = undefined,
            .triIndices = undefined,
            .aabb = undefined,
        };

        var prng = std.rand.DefaultPrng.init(0);
        var rand = prng.random();

        errdefer s.deinit();
        // FIXME, free it all after
        // create a polycomponent with just outline of bitmap, so we have some poly outline
        s.polyComponents = std.ArrayList(PolygonComponent).initCapacity(allocator, 1) catch |err| {
            return err;
        };

        var verts = std.ArrayList(Vec2).initCapacity(allocator, 4) catch |err| {
            return err;
        };
        const widthf = @intToFloat(f32, width);
        const heightf = @intToFloat(f32, height);
        const off = vec2(-(widthf / 2) * scale, -(heightf / 2) * scale);

        var wobbleGrid = createWobbleGrid(allocator, rand, width, height, scale, off) catch |err| {
            return err;
        };
        defer wobbleGrid.deinit();

        try verts.append(vec2(0, 0).add(off));
        try verts.append(vec2(widthf * scale, 0).add(off));
        try verts.append(vec2(widthf * scale, heightf * scale).add(off));
        try verts.append(vec2(0, heightf * scale).add(off));
        var newpc = PolygonComponent{
            .negative = false,
            .verts = verts.items,
        };
        try s.polyComponents.append(newpc);

        // allocate for triangles and vertices
        s.triVerts = std.ArrayList(Vec2).initCapacity(allocator, 1) catch |err| {
            return err;
        };
        s.triIndices = std.ArrayList([3]usize).initCapacity(allocator, 1) catch |err| {
            return err;
        };

        var y: usize = 0;
        var ti: usize = 0;
        while (y < height) : (y += 1) {
            var x: usize = 0;
            while (x < width) : (x += 1) {
                if (data[width * y + x] > 0) {
                    // generate quad
                    // 4 verts
                    try s.triVerts.append(wobbleGridAt(wobbleGrid, x, y, width));
                    try s.triVerts.append(wobbleGridAt(wobbleGrid, x, y + 1, width));
                    try s.triVerts.append(wobbleGridAt(wobbleGrid, x + 1, y + 1, width));
                    try s.triVerts.append(wobbleGridAt(wobbleGrid, x + 1, y, width));
                    // 2 tris
                    try s.triIndices.append(.{ ti * 4 + 0, ti * 4 + 1, ti * 4 + 2 });
                    try s.triIndices.append(.{ ti * 4 + 2, ti * 4 + 3, ti * 4 + 0 });
                    ti += 1;
                }
            }
        }

        s.aabb = calcAABB(&s.triVerts);
        return s;
    }

    fn triangulateGroup(self: *Self, allocator: Allocator, polyComponents: []PolygonComponent) !void {
        // calc total numPoints
        var numPoints: u32 = 0;
        for (polyComponents) |pc| {
            numPoints += @intCast(u32, pc.verts.len);
        }

        // setup memory buffer
        const memRequired = mpe.MPE_PolyMemoryRequired(numPoints);
        const memory = try allocator.alignedAlloc(u8, 8, memRequired);
        @memset(memory.ptr, 0x00, memRequired);
        defer allocator.free(memory);

        // process
        var polyContext: mpe.MPEPolyContext = undefined;
        if (mpe.MPE_PolyInitContext(&polyContext, memory.ptr, numPoints) == 1) {
            for (polyComponents) |pc| {
                var i: usize = 0;
                while (i < pc.verts.len) : (i = i + 1) {
                    const pt = mpe.MPE_PolyPushPoint(&polyContext);
                    pt.*.X = pc.verts[i].x;
                    pt.*.Y = pc.verts[i].y;
                }
                if (pc.negative) {
                    mpe.MPE_PolyAddHole(&polyContext);
                } else {
                    mpe.MPE_PolyAddEdge(&polyContext);
                }
            }

            mpe.MPE_PolyTriangulate(&polyContext);

            const tioff = self.triIndices.items.len;
            std.log.info("tri OK tricount {} tioff={}\n", .{ polyContext.TriangleCount, tioff });

            var ti: usize = 0;
            while (ti < polyContext.TriangleCount) : (ti += 1) {
                const tri = polyContext.Triangles[ti];
                try self.triIndices.append(.{ (tioff + ti) * 3, (tioff + ti) * 3 + 1, (tioff + ti) * 3 + 2 });
                try self.triVerts.append(vec2(tri.*.Points[0].*.X, tri.*.Points[0].*.Y));
                try self.triVerts.append(vec2(tri.*.Points[1].*.X, tri.*.Points[1].*.Y));
                try self.triVerts.append(vec2(tri.*.Points[2].*.X, tri.*.Points[2].*.Y));
            }
        }
    }

    pub fn triangulate(self: *Self, allocator: Allocator) !void {
        // allocate for triangles and vertices
        self.triVerts = std.ArrayList(Vec2).initCapacity(allocator, 1) catch |err| {
            return err;
        };
        self.triIndices = std.ArrayList([3]usize).initCapacity(allocator, 1) catch |err| {
            return err;
        };

        try triangulateGroup(self, allocator, self.polyComponents.items);
    }

    pub fn deinit(self: *Self) void {
        self.triVerts.deinit();
        self.triIndices.deinit();
        self.polyComponents.deinit();
    }

    fn posToUV(aabb: Game.Rect, p:Vec2, w:f32, h:f32) Vec2 {
        var tx:f32 = undefined;
        var ty:f32 = undefined;

        var px = p.x - aabb.tl.x;
        var py = p.y - aabb.tl.y;

        // tx,ty are now fraction across entire image 0 to 1
        tx = px / aabb.width();
        ty = py / aabb.height();

        // repeat based on w,h
        tx *= aabb.width() / w;
        ty *= aabb.height() / h;

        return vec2(tx, ty);
    }

    pub fn renderTiledTexture(self: *const Self, renderer: *Game.Renderer, world: *Game.World, pos: Vec2, scale: f32, sprite:*Game.Sprite) void {
        for (self.triIndices.items) |triIndex| {
            const v0model = self.triVerts.items[triIndex[0]];
            const v1model = self.triVerts.items[triIndex[1]];
            const v2model = self.triVerts.items[triIndex[2]];

            const v0world = v0model.scale(scale).add(pos);
            const v1world = v1model.scale(scale).add(pos);
            const v2world = v2model.scale(scale).add(pos);

            const v0view = world.worldToView(v0world);
            const v1view = world.worldToView(v1world);
            const v2view = world.worldToView(v2world);

            const w = @intToFloat(f32, sprite.sheetSurf.width);
            const h = @intToFloat(f32, sprite.sheetSurf.height);

            const uv0 = posToUV(self.aabb, v0model, w, h);
            const uv1 = posToUV(self.aabb, v1model, w, h);
            const uv2 = posToUV(self.aabb, v2model, w, h);

            // draw triangle
            renderer.drawTriangleTex(
                @floatToInt(i32, v0view.x), @floatToInt(i32, v0view.y),
                @floatToInt(i32, v1view.x), @floatToInt(i32, v1view.y),
                @floatToInt(i32, v2view.x), @floatToInt(i32, v2view.y),
                uv0.x, uv0.y,
                uv1.x, uv1.y,
                uv2.x, uv2.y,
                sprite.sheetSurf);

//            // draw outline
//            renderer.drawLine(@floatToInt(i32, v0view.x), @floatToInt(i32, v0view.y), @floatToInt(i32, v1view.x), @floatToInt(i32, v1view.y), 0xFF000000);
//            renderer.drawLine(@floatToInt(i32, v1view.x), @floatToInt(i32, v1view.y), @floatToInt(i32, v2view.x), @floatToInt(i32, v2view.y), 0xFF000000);
//            renderer.drawLine(@floatToInt(i32, v2view.x), @floatToInt(i32, v2view.y), @floatToInt(i32, v0view.x), @floatToInt(i32, v0view.y), 0xFF000000);

        }
    }

    pub fn render(self: *const Self, renderer: *Game.Renderer, world: *Game.World, pos: Vec2, scale: f32) void {
        const outline = false;
        const lines = false;

        for (self.triIndices.items) |triIndex| {
            const v0 = world.worldToView(self.triVerts.items[triIndex[0]].scale(scale).add(pos));
            const v1 = world.worldToView(self.triVerts.items[triIndex[1]].scale(scale).add(pos));
            const v2 = world.worldToView(self.triVerts.items[triIndex[2]].scale(scale).add(pos));

            // draw triangle
            renderer.drawTriangle(
                @floatToInt(i32, v0.x), @floatToInt(i32, v0.y),
                @floatToInt(i32, v1.x), @floatToInt(i32, v1.y),
                @floatToInt(i32, v2.x), @floatToInt(i32, v2.y),
                0xFFFF0000);

            if (lines) {
                // draw outline
                renderer.drawLine(@floatToInt(i32, v0.x), @floatToInt(i32, v0.y), @floatToInt(i32, v1.x), @floatToInt(i32, v1.y), 0xFFFFFFFF);
                renderer.drawLine(@floatToInt(i32, v1.x), @floatToInt(i32, v1.y), @floatToInt(i32, v2.x), @floatToInt(i32, v2.y), 0xFFFFFFFF);
                renderer.drawLine(@floatToInt(i32, v2.x), @floatToInt(i32, v2.y), @floatToInt(i32, v0.x), @floatToInt(i32, v0.y), 0xFFFFFFFF);
            }
        }

        // polygon outline
        if (outline) {
            var prev = world.worldToView(self.polyComponents.items[0].verts[0].scale(scale).add(pos));
            var i: usize = 1;
            while (i < self.polyComponents.items[0].verts.len + 1) : (i += 1) {
                const next = world.worldToView(self.polyComponents.items[0].verts[i % self.polyComponents.items[0].verts.len].scale(scale).add(pos));
                renderer.drawLine(@floatToInt(i32, prev.x), @floatToInt(i32, prev.y), @floatToInt(i32, next.x), @floatToInt(i32, next.y), 0xFF00FFFF);
                prev = next;
            }
        }
    }

    pub fn collideCircle(self: *const Self, pos: Vec2, radius: f32) ?[2]Vec2 {
        for (self.triIndices.items) |triIndex| {
            const pt0 = self.triVerts.items[triIndex[0]];
            const pt1 = self.triVerts.items[triIndex[1]];
            const pt2 = self.triVerts.items[triIndex[2]];
            //std.log.info("pts = {},{},{}", .{pt0, pt1, pt2});

            if (Game.Collision.checkCollisionPointCircle(pt0, pos, radius)) |inter| {
                return inter;
            }
            if (Game.Collision.checkCollisionPointCircle(pt1, pos, radius)) |inter| {
                return inter;
            }
            if (Game.Collision.checkCollisionPointCircle(pt2, pos, radius)) |inter| {
                return inter;
            }

            if (Game.Collision.intersectLineCircle(pos, radius, pt0, pt1)) |inter| {
                return inter;
            }
            if (Game.Collision.intersectLineCircle(pos, radius, pt1, pt2)) |inter| {
                return inter;
            }
            if (Game.Collision.intersectLineCircle(pos, radius, pt2, pt0)) |inter| {
                return inter;
            }

            if (Game.Collision.checkCollisionPointTriangle(pos, pt0, pt1, pt2)) {
                std.log.info("FIXME CPT", .{});
                return .{ pos, vec2(0, 0) }; // FIXME
            }
        }

        return null;
    }

};

//var mypoly: Game.Polygon = undefined;
//    const pv = [_]Vec2{ vec2(-0.3333333333333349, -1), vec2(-0.3580246913580249, -0.9917695473251104), vec2(-0.3662551440329239, -0.9670781893004227), vec2(-0.3662551440329239, -0.7942386831275716), vec2(-0.3333333333333349, -0.753086419753086), vec2(-0.28395061728395254, -0.753086419753086), vec2(-0.29218106995884924, -0.7201646090535087), vec2(-0.32510288065843823, -0.662551440329225), vec2(-0.4567901234567919, -0.555555555555566), vec2(-0.46502057613168857, -0.4897119341563926), vec2(-0.46502057613168857, 0.7860082304526632), vec2(-0.44855967078189524, 0.8683127572016347), vec2(-0.3333333333333349, 0.9835390946502021), vec2(-0.25102880658436355, 1), vec2(0.2592592592592602, 1), vec2(0.34156378600823156, 0.9835390946502021), vec2(0.4485596707818929, 0.8683127572016347), vec2(0.46502057613168857, 0.7860082304526632), vec2(0.46502057613168857, -0.4897119341563926), vec2(0.45679012345678954, -0.555555555555566), vec2(0.33333333333333254, -0.662551440329225), vec2(0.29218106995884685, -0.753086419753086), vec2(0.3662551440329216, -0.7613168724279943), vec2(0.3744855967078182, -0.7942386831275716), vec2(0.3744855967078182, -0.9670781893004227), vec2(0.3662551440329216, -0.9917695473251104) };
//
//    var polycomps = [1]PolygonComponent{
//        PolygonComponent{
//            .negative = false,
//            .verts = &pv,
//        },
//    };
//
//    mypoly = Polygon.init(std.heap.page_allocator, &polycomps) catch |err| {
//        return err;
//    };
//
