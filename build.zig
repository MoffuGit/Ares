const std = @import("std");
const XCFrameworkStep = @import("build/XCFrameworkStep.zig");
const LibtoolStep = @import("build/LibtoolStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const clone_chromium = cloneChromiumStep(b);

    const exe_tests = b.addTest(.{
        .root_module = rootModule(
            b,
            target,
            optimize,
            "src/test.zig",
        ),
    });
    exe_tests.step.dependOn(clone_chromium);
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(exe_tests).step);

    const mod = rootModule(
        b,
        target,
        optimize,
        "src/lib.zig",
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
) *std.Build.Module {
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
            .{ .name = "zlob", .module = b.dependency("zlob", .{
                .target = target,
                .optimize = optimize,
            }).module("zlob_core") },
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

    addTestOptions(mod, b);

    return mod;
}

const TestPath = "test";
const ChromiumPath = TestPath ++ "/chromium";
const ChromiumUrl = "https://github.com/chromium/chromium.git";

pub fn cloneChromiumStep(b: *std.Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "clone chromium",
        .owner = b,
        .makeFn = cloneChromiumMake,
    });
    return step;
}

pub fn addTestOptions(mod: *std.Build.Module, b: *std.Build) void {
    const test_options = b.addOptions();
    test_options.addOption([]const u8, "chromium_path", b.pathFromRoot(ChromiumPath));
    test_options.addOption(bool, "benchmark", for (b.args orelse &.{}) |arg| {
        if (std.mem.indexOf(u8, arg, "benchmark") != null) break true;
    } else false);

    mod.addOptions("test_options", test_options);
}

fn cloneChromiumMake(step: *std.Build.Step, opts: std.Build.Step.MakeOptions) anyerror!void {
    const b = step.owner;
    const io = b.graph.io;
    const dest = b.pathFromRoot(ChromiumPath);
    const git_dir = b.pathJoin(&.{ dest, ".git" });

    if (std.Io.Dir.accessAbsolute(io, git_dir, .{})) |_| return else |_| {}

    std.Io.Dir.cwd().createDirPath(io, b.pathFromRoot(TestPath)) catch |e|
        return step.fail("unable to create testdata dir: {s}", .{@errorName(e)});

    var node = opts.progress_node.start("git clone chromium", 0);
    defer node.end();

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "git",                "clone",
            "--depth",            "1",
            "--filter=blob:none", ChromiumUrl,
            dest,
        },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    const term = child.wait(io) catch |e|
        return step.fail("failed to spawn git: {s}", .{@errorName(e)});

    switch (term) {
        .exited => |code| if (code != 0)
            return step.fail("git clone exited with code {d}", .{code}),
        else => return step.fail("git clone terminated unexpectedly", .{}),
    }
}
