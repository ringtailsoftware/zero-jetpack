const std = @import("std");

var optimize:std.builtin.OptimizeMode = undefined;
var target:std.Build.ResolvedTarget = undefined;

// https://github.com/ringtailsoftware/zig-embeddir
pub fn addAssetsOption(b: *std.Build, exe:anytype, assetpath:[]const u8) !void {
    var options = b.addOptions();

    var files = std.ArrayList([]const u8).init(b.allocator);
    defer files.deinit();

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fs.cwd().realpath(assetpath, buf[0..]);

    var dir = try std.fs.openDirAbsolute(path, .{.iterate=true});
    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .file) {
            continue;
        }
        try files.append(b.dupe(file.name));
    }
    options.addOption([]const []const u8, "files", files.items);
    exe.step.dependOn(&options.step);

    const assets = b.addModule("assets", .{
        .root_source_file = options.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("assets", assets);
}

fn addExample(b: *std.Build, comptime name: []const u8, flags: ?[]const []const u8, sources: ?[]const []const u8, includes: ?[]const []const u8) !void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_source_file = b.path("src/" ++ name ++ "/" ++ name ++ ".zig"),
        .target = target,
        .optimize = optimize,
        .strip = false,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.addIncludePath(b.path("src/" ++ name));

    if (includes != null) {
        for (includes.?) |inc| {
            exe.addIncludePath(b.path(inc));
        }
    }
    if (flags != null and sources != null) {
        exe.addCSourceFiles(.{ 
            .files = sources.?,
            .flags = flags.?,
        });
    }

    const zeptolibc_dep = b.dependency("zeptolibc", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zeptolibc", zeptolibc_dep.module("zeptolibc"));
    exe.root_module.addIncludePath(zeptolibc_dep.path("include"));
    exe.root_module.addIncludePath(zeptolibc_dep.path("include/zeptolibc"));

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_mod = zigimg_dep.module("zigimg");
    exe.root_module.addImport("zigimg", zigimg_mod);

    exe.addIncludePath(b.path("src/"));

    // if assets dir exists in project, add @embedFile everything in it
    if (std.fs.cwd().statFile("src/" ++ name ++ "/assets")) |stat| {
        switch(stat.kind) {
            .directory => try addAssetsOption(b, exe, "src/" ++ name ++ "/assets"),
            else => return error.AssetsDirectoryIsAFile,
        }
    } else |err| switch(err) {
        else => {},
    }

    b.installArtifact(exe);
}

pub fn build(b: *std.Build) !void {
    const hosttarget = b.standardTargetOptions(.{});
    optimize = b.standardOptimizeOption(.{});

    target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    b.installFile("src/jetpack/index.html", "index.html");
    b.installFile("src/pcm-processor.js", "pcm-processor.js");
    b.installFile("src/wasmpcm.js", "wasmpcm.js");
    b.installFile("src/ringbuf.js", "ringbuf.js");
    b.installFile("src/coi-serviceworker.js", "coi-serviceworker.js");
    b.installFile("src/unmute.js", "unmute.js");


    try addExample(b, "jetpack", &.{"-Wall"}, &.{ "src/jetpack/olive.c/olive.c", "src/jetpack/MPE_fastpoly2tri.c", "src/jetpack/stb_truetype.c", "src/jetpack/pocketmod.c" }, null);

    // web server
    const serve_exe = b.addExecutable(.{
        .name = "serve",
        .root_source_file = b.path("httpserver/serve.zig"),
        .target = hosttarget,
        .optimize = optimize,
    });

    const mod_server = b.addModule("StaticHttpFileServer", .{
        .root_source_file = b.path("httpserver/root.zig"),
        .target = hosttarget,
        .optimize = optimize,
    });

    mod_server.addImport("mime", b.dependency("mime", .{
        .target = hosttarget,
        .optimize = optimize,
    }).module("mime"));

    serve_exe.root_module.addImport("StaticHttpFileServer", mod_server);

    const run_serve_exe = b.addRunArtifact(serve_exe);
    if (b.args) |args| run_serve_exe.addArgs(args);

    const serve_step = b.step("serve", "Serve a directory of files");
    serve_step.dependOn(&run_serve_exe.step);

}
