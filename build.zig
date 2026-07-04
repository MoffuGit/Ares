const std = @import("std");
const prof = @import("prof/build.zig");
const XCFrameworkStep = @import("build/XCFrameworkStep.zig");
const LibtoolStep = @import("build/LibtoolStep.zig");
const @"test" = @import("test/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const requested = prof.option(b);
    const test_opts = @"test".options(b);

    const clone_chromium = @"test".cloneChromiumStep(b);
    const bench_filter = b.option([]const u8, "bench-filter", "Only run benchmarks whose test name contains this text");

    const exe_tests = b.addTest(.{
        .root_module = rootModule(
            b,
            target,
            optimize,
            "src/test.zig",
            .{ .level = requested orelse .none },
            test_opts,
        ),
    });
    exe_tests.step.dependOn(clone_chromium);
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(exe_tests).step);

    const bench_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/bench.zig", .{
            .level = requested orelse .general,
            .bench = true,
        }, test_opts),
        .test_runner = .{ .path = b.path("prof/bench_runner.zig"), .mode = .simple },
        .filters = if (bench_filter) |filter| &.{filter} else &.{},
    });

    const bench_artifact = b.addInstallArtifact(
        bench_tests,
        .{ .dest_dir = .{ .override = .{ .custom = "benchs" } } },
    );

    const install_bench_step = b.step("install_bench", "Create bench binaries for debugging");
    install_bench_step.dependOn(&bench_artifact.step);

    bench_tests.step.dependOn(clone_chromium);
    const run_bench = b.addRunArtifact(bench_tests);
    run_bench.argv.shrinkRetainingCapacity(1);
    run_bench.stdio = .inherit;
    b.step("bench", "Run benchmarks").dependOn(&run_bench.step);

    const mod = rootModule(
        b,
        target,
        optimize,
        "src/lib.zig",
        .{ .level = requested orelse .none },
        null,
    );

    // if (b.lazyDependency("macos", .{
    //     .target = target,
    //     .optimize = optimize,
    // })) |macos_dep| {
    //     mod.addImport(
    //         "macos",
    //         macos_dep.module("macos"),
    //     );
    //     mod.linkLibrary(
    //         macos_dep.artifact("macos"),
    //     );
    // }

    const lib = b.addLibrary(.{
        .name = "odyssey",
        .root_module = mod,
    });

    const lib_install = b.addInstallArtifact(lib, .{});
    const lib_step = b.step("lib", "Compile and Install XCFramework Odyssey Kit");

    if (lib_install.emitted_bin) |lazy_path| {
        var libs: std.ArrayList(std.Build.LazyPath) = .empty;
        libs.append(b.allocator, lazy_path) catch {
            @panic("We cannot append the lib");
        };

        const libtool = LibtoolStep.create(
            b,
            .{
                .name = "odyssey",
                .out_name = "libodyssey-aarch64-bundle.a",
                .sources = libs.items,
                .extract_objects = true,
            },
        );

        libtool.step.dependOn(&lib_install.step);

        const xcframework = XCFrameworkStep.create(
            b,
            .{
                .name = "OdysseyKit",
                .libraries = &.{
                    XCFrameworkStep.Library{
                        .library = libtool.output,
                        .headers = .{ .cwd_relative = "include" },
                        .dsym = null,
                    },
                },
                .out_path = "macos/OdysseyKit.xcframework",
            },
        );

        xcframework.step.dependOn(libtool.step);

        lib_step.dependOn(xcframework.step);
    }

    lib_step.dependOn(&lib_install.step);
}

fn rootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_source: []const u8,
    prof_opts: prof.Options,
    test_opts: ?@"test".Options,
) *std.Build.Module {
    const prof_mod = prof.module(b, target, optimize, prof_opts);
    const zqlite = b.dependency("zqlite", .{
        .target = target,
        .optimize = optimize,
    });

    const objc = b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = .off,
        .imports = &.{
            .{ .name = "prof", .module = prof_mod },
            .{ .name = "zqlite", .module = zqlite.module("zqlite") },
            .{ .name = "objc", .module = objc.module("objc") },
        },
    });
    const default_sqlite3_build = [_][]const u8{"-std=c99"};

    mod.addCSourceFile(.{
        .file = b.path("lib/sqlite3.c"),
        .flags = &default_sqlite3_build,
    });
    mod.addIncludePath(b.path("lib"));

    if (test_opts) |opts| @"test".addOptions(mod, b, opts);
    return mod;
}
