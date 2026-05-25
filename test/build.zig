const std = @import("std");

const TestPath = "test";
const ChromiumPath = TestPath ++ "/chromium";
const ChromiumUrl = "https://github.com/chromium/chromium.git";

pub const Options = struct {
    chromium_path: []const u8,
};

pub fn build(b: *std.Build) void {
    b.step("chromium", "Clone Chromium test data").dependOn(cloneChromiumStep(b));
}

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

pub fn options(b: *std.Build) Options {
    return .{
        .chromium_path = b.pathFromRoot(ChromiumPath),
    };
}

pub fn addOptions(mod: *std.Build.Module, b: *std.Build, opts: Options) void {
    const build_options = b.addOptions();
    build_options.addOption([]const u8, "chromium_path", opts.chromium_path);
    mod.addOptions("test_build", build_options);
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
