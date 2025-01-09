const std = @import("std");
const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;
const Rect = Game.Rect;

pub const World = struct {
    const Self = @This();
    worldWindow: Rect,
    viewBox: Rect,
    worldBounds: Rect,
    screenViewport: Rect,
    worldZoom: f32,
    viewBoxFraction: f32,
    gravity: f32,

    pub fn init(worldSize: Vec2, screenSize: Vec2) Self {
        return Self{
            .worldWindow = Rect{ .tl = vec2(0, 0), .br = vec2(0, 0) }, // the piece of the world being looked at
            .viewBox = Rect{ .tl = vec2(0, 0), .br = vec2(0, 0) }, // the box in which player can move without scrolling
            .screenViewport = Rect{ .tl = vec2(0, 0), .br = screenSize }, // the drawable rect on the screen
            .worldBounds = Rect{ .tl = worldSize.scale(-0.5), .br = worldSize.scale(0.5) }, // navigable world area
            .worldZoom = 1.0, // viewing scale
            .viewBoxFraction = 0.2, // fraction of world window to cover with viewBox
            .gravity = 400,
        };
    }

    pub fn setScreenViewport(self: *Self, vp: Rect, zoom: f32) void {
        // update the viewport
        self.screenViewport = vp;
        self.worldZoom = zoom;
        const vp_half_dim = vp.br.sub(vp.tl).scale(0.5);
        // recalculate world window pos, so aspect ratio matches viewport
        const mid_of_ww = self.worldWindow.br.sub(self.worldWindow.tl).scale(0.5).add(self.worldWindow.tl);
        self.worldWindow.tl = mid_of_ww.sub(vp_half_dim).scale(1.0 / zoom);
        self.worldWindow.br = mid_of_ww.add(vp_half_dim).scale(1.0 / zoom);
        // recalculate viewbox
        const mid_of_vb = self.viewBox.br.sub(self.viewBox.tl).scale(0.5).add(self.viewBox.tl);
        const ww_dim = self.worldWindow.br.sub(self.worldWindow.tl);
        self.viewBox.tl = mid_of_vb.sub(ww_dim.scale(self.viewBoxFraction / 2));
        self.viewBox.br = mid_of_vb.add(ww_dim.scale(self.viewBoxFraction / 2));
    }

    pub fn trackWorldWindow(self: *Self, pos: Vec2) void {
        const dim = (self.viewBox.br.sub(self.viewBox.tl));

        if (pos.x < self.viewBox.tl.x) {
            self.viewBox.tl.x = pos.x;
            self.viewBox.br.x = pos.x + dim.x;
        }
        if (pos.x > self.viewBox.br.x) {
            self.viewBox.br.x = pos.x;
            self.viewBox.tl.x = pos.x - dim.x;
        }
        if (pos.y < self.viewBox.tl.y) {
            self.viewBox.tl.y = pos.y;
            self.viewBox.br.y = pos.y + dim.y;
        }
        if (pos.y > self.viewBox.br.y) {
            self.viewBox.br.y = pos.y;
            self.viewBox.tl.y = pos.y - dim.y;
        }

        // worldWindow tracks viewBox
        const ww_half_dim = (self.worldWindow.br.sub(self.worldWindow.tl)).scale(0.5);
        const mid_of_vb = self.viewBox.br.sub(self.viewBox.tl).scale(0.5).add(self.viewBox.tl);
        self.worldWindow.tl = mid_of_vb.sub(ww_half_dim);
        self.worldWindow.br = mid_of_vb.add(ww_half_dim);
    }

    pub fn worldToViewScale(self: *const Self) Vec2 {
        return vec2((self.screenViewport.br.x - self.screenViewport.tl.x) / (self.worldWindow.br.x - self.worldWindow.tl.x), (self.screenViewport.br.y - self.screenViewport.tl.y) / (self.worldWindow.br.y - self.worldWindow.tl.y));
    }

    pub fn worldToView(self: *const Self, w: Vec2) Vec2 {
        // scale factor
        const s = self.worldToViewScale();
        // point on viewport
        const v = vec2(self.screenViewport.tl.x + ((w.x - self.worldWindow.tl.x) * s.x), self.screenViewport.tl.y + ((w.y - self.worldWindow.tl.y) * s.y));
        return v;
    }

    pub fn render(self: *Self, renderer: *Game.Renderer) void {
        const showBounds = false;
        if (showBounds) {
            renderer.drawRect(self.screenViewport, 0xFF0000FF); // edge of viewport
            const bounds = Rect{ .tl = self.worldToView(self.worldBounds.tl), .br = self.worldToView(self.worldBounds.br) };
            renderer.drawRect(bounds, 0xFF00FFFF); // edge of the world
            const vb = Rect{ .tl = self.worldToView(self.viewBox.tl), .br = self.worldToView(self.viewBox.br) };
            renderer.drawRect(vb, 0xFFFFFFFF); // viewbox
        }

        const bgcircles = false;
        if (bgcircles) {
            // some background circles in fixed locations
            const r = 20 * self.worldZoom;
            var y: f32 = self.worldBounds.tl.y;
            var red: u8 = 0x80;
            var blue: u8 = 0x00;
            while (y < self.worldBounds.br.y) : (y += 200) {
                var x: f32 = self.worldBounds.tl.x;
                blue +%= 1;
                while (x < self.worldBounds.br.x) : (x += 200) {
                    red +%= 1;
                    if (x >= self.worldWindow.tl.x - r and x <= self.worldWindow.br.x + r and y >= self.worldWindow.tl.y - r and y <= self.worldWindow.br.y + r) {
                        const cpos = self.worldToView(vec2(x, y));
                        renderer.circle(Game.compat_floatToInt(i32, cpos.x), Game.compat_floatToInt(i32, cpos.y), Game.compat_floatToInt(i32, r), 0xFFFF00FF);
                    }
                }
            }
        }
    }
};
