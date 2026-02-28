const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core library module (database + crawler + manga types, no SDL2).
    const core_mod = b.addModule("otaku", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.linkSystemLibrary("sqlite3", .{});
    core_mod.linkSystemLibrary("c", .{});

    // Main executable – includes the SDL2/TTF UI layer.
    const exe = b.addExecutable(.{
        .name = "otaku",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "otaku", .module = core_mod },
            },
        }),
    });
    exe.root_module.linkSystemLibrary("SDL2", .{});
    exe.root_module.linkSystemLibrary("SDL2_ttf", .{});
    exe.root_module.linkSystemLibrary("sqlite3", .{});
    exe.root_module.linkSystemLibrary("c", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the Otaku manga reader");
    run_step.dependOn(&run_cmd.step);

    // Unit tests – only the core library modules (no SDL2 required).
    const core_tests = b.addTest(.{
        .root_module = core_mod,
    });
    const run_core_tests = b.addRunArtifact(core_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_core_tests.step);
}
