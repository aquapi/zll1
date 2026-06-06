const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zll1 = b.addModule("zll1", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/root.zig"),
    });

    {
        const lib = b.addLibrary(.{
            .name = "zll1",
            .root_module = zll1,
        });
        b.installArtifact(lib);
    }

    // Run tests
    {
        const run_test = b.addRunArtifact(b.addTest(.{
            .root_module = zll1,
        }));
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_test.step);
    }

    // Run examples
    const example_step = b.step("example", "Build and run an example.");
    const example_assembly_step = b.step("example-asm", "Build and emit an example's assembly.");

    if (b.args) |args| {
        const example_name = args[0];

        // Check whether path exists
        const path = try std.fmt.allocPrint(b.allocator, "examples/{s}/main.zig", .{example_name});
        try std.Io.Dir.cwd().access(b.graph.io, path, .{});

        // Build example file
        const exe = b.addExecutable(.{
            .name = example_name,
            .use_llvm = true,
            .root_module = b.createModule(.{ .root_source_file = b.path(path), .target = target, .optimize = optimize, .strip = true }),
        });
        exe.root_module.addImport("zll1", zll1);
        b.installArtifact(exe);

        {
            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            example_step.dependOn(&run_cmd.step);
        }

        // Emit ASM
        {
            const asm_step = b.step(example_name, "Emit the example ASM file");
            const install_asm = b.addInstallBinFile(exe.getEmittedAsm(), try std.fmt.allocPrint(b.allocator, "{s}.s", .{example_name}));
            asm_step.dependOn(&install_asm.step);

            example_assembly_step.dependOn(asm_step);
        }
    }
}
