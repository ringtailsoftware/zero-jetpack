const std = @import("std");
const Game = @import("game.zig").Game;
const vec2 = Game.vec2;
const Vec2 = Game.Vec2;


pub const Collision = struct {
    // https://stackoverflow.com/a/10392860/283981
    pub fn intersectLineCircle(location: Vec2, radius: f32, lineFrom: Vec2, lineTo: Vec2) ?[2]Vec2 {
        const ac = location.sub(lineFrom);
        const ab = lineTo.sub(lineFrom);

        const ab2 = ab.dot(ab);
        const acab = ac.dot(ab);
        var t = acab / ab2;

        if (t < 0) {
            t = 0;
        } else if (t > 1) {
            t = 1;
        }

        const h = (ab.scale(t).add(lineFrom)).sub(location);
        const h2 = h.dot(h);

        if (h2 <= (radius * radius)) {
            // https://forum.unity.com/threads/how-do-i-find-the-closest-point-on-a-line.340058/
            const lineDir = ab.normalize();
            const d = ac.dot(lineDir);

            const contact = lineFrom.add(lineDir.scale(d));

            // calc normal by projecting from contact point towards location
            const a = std.math.atan2(f32, contact.y - location.y, contact.x - location.x);
            //        const n = vec2(std.math.cos(a),std.math.sin(a)).normalize().scale(-1);
            const n = vec2(std.math.cos(a), std.math.sin(a)).scale(-1);
            return .{ contact, n };
        } else {
            return null;
        }
    }

    // from raylib
    pub fn checkCollisionCircles(centre1: Vec2, radius1: f32, centre2: Vec2, radius2: f32) bool {
        const dx = centre2.x - centre1.x; // X distance between centres
        const dy = centre2.y - centre1.y; // Y distance between centres
        const distance_sq = dx * dx + dy * dy; // Distance between centres
        return distance_sq <= (radius1 + radius2) * (radius1 + radius2);
    }

    pub fn checkCollisionPointCircle(point: Vec2, centre: Vec2, radius: f32) ?[2]Vec2 {
        if (checkCollisionCircles(point, 0, centre, radius)) {
            // project intersection point onto edge of circle
            const a = std.math.atan2(f32, point.y - centre.y, point.x - centre.x);
            const n = vec2(std.math.cos(a), std.math.sin(a)).scale(-1); //.normalize().scale(-1);
            return .{ vec2(centre.x + std.math.cos(a) * radius, centre.y + std.math.sin(a) * radius), n };
        } else {
            return null;
        }
    }

    pub fn checkCollisionPointTriangle(point: Vec2, p1: Vec2, p2: Vec2, p3: Vec2) bool {
        var collision = false;

        var alpha = ((p2.y - p3.y) * (point.x - p3.x) + (p3.x - p2.x) * (point.y - p3.y)) /
            ((p2.y - p3.y) * (p1.x - p3.x) + (p3.x - p2.x) * (p1.y - p3.y));

        var beta = ((p3.y - p1.y) * (point.x - p3.x) + (p1.x - p3.x) * (point.y - p3.y)) /
            ((p2.y - p3.y) * (p1.x - p3.x) + (p3.x - p2.x) * (p1.y - p3.y));

        var gamma = 1.0 - alpha - beta;

        if ((alpha > 0) and (beta > 0) and (gamma > 0)) collision = true;

        return collision;
    }
};

