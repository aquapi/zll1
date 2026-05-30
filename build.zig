const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zll1 = b.addModule("zll1", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "zll1",
        .root_module = zll1,
    });
    b.installArtifact(lib);

    const run_test = b.addRunArtifact(
      b.addTest(.{
        .root_module = zll1
      })
    );
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_test.step);
}
