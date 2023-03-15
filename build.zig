const std = @import("std");

var target: std.zig.CrossTarget = undefined;

// https://github.com/ringtailsoftware/zig-embeddir
pub fn addAssetsOption(b: *std.build.Builder, exe: anytype, comptime name: []const u8) !void {
    var options = b.addOptions();

    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();

    var buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path = try std.fs.cwd().realpath("src/" ++ name ++ "/assets", buf[0..]);

    var dir = try std.fs.openIterableDirAbsolute(path, .{});
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .File) {
            continue;
        }
        try files.append(b.dupe(file.name));
    }
    options.addOption([]const []const u8, "files", files.items);
    exe.step.dependOn(&options.step);

    const assets = b.createModule(.{
        .source_file = options.getSource(),
        .dependencies = &.{},
    });
    exe.addModule("assets", assets);
}

fn addApp(b: *std.build.Builder, comptime name: []const u8, flags: ?[]const []const u8, sources: ?[]const []const u8, includes: ?[]const []const u8) !void {
    const lib = b.addSharedLibrary(.{ .name = name, .root_source_file = .{ .path = "src/" ++ name ++ "/" ++ name ++ ".zig" }, .target = target, .optimize = .ReleaseFast });

    lib.rdynamic = true;
    lib.strip = false;
    lib.install();
    lib.addIncludePath("src/" ++ name);

    if (includes != null) {
        for (includes.?) |inc| {
            lib.addIncludePath(inc);
        }
    }
    if (flags != null and sources != null) {
        lib.addCSourceFiles(sources.?, flags.?);
    }

    try addAssetsOption(b, lib, name);

    const zigimg = b.createModule(.{
        .source_file = .{ .path = "src/" ++ name ++ "/zigimg/zigimg.zig" },
        .dependencies = &.{},
    });
    lib.addModule("zigimg", zigimg);

    const zlm = b.createModule(.{
        .source_file = .{ .path = "src/" ++ name ++ "/zlm/zlm.zig" },
        .dependencies = &.{},
    });
    lib.addModule("zlm", zlm);
}

pub fn build(b: *std.build.Builder) !void {
    target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    } });

    b.installFile("src/jetpack/index.html", "index.html");
    b.installFile("src/pcm-processor.js", "pcm-processor.js");
    b.installFile("src/wasmpcm.js", "wasmpcm.js");
    b.installFile("src/ringbuf.js", "ringbuf.js");
    b.installFile("src/coi-serviceworker.js", "coi-serviceworker.js");
    b.installFile("src/unmute.js", "unmute.js");

    try addApp(b, "jetpack", &.{"-Wall"}, &.{ "src/jetpack/olive.c/olive.c", "src/jetpack/MPE_fastpoly2tri.c", "src/jetpack/stb_truetype.c", "src/jetpack/pocketmod.c" }, null);
}
