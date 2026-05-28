//! A zig builder step that runs "libtool" against a list of libraries
//! in order to create a single combined static library.
const LibtoolStep = @This();

const std = @import("std");
const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    /// The name of this step.
    name: []const u8,

    /// The filename (not the path) of the file to create. This will
    /// be placed in a unique hashed directory. Use out_path to access.
    out_name: []const u8,

    /// Library files (.a) to combine.
    sources: []LazyPath,

    /// Extract objects from each source archive before repacking with libtool.
    extract_objects: bool = false,
};

/// The step to depend on.
step: *Step,

/// The output file from the libtool run.
output: LazyPath,

/// Run libtool against a list of library files to combine into a single
/// static library.
pub fn create(b: *std.Build, opts: Options) *LibtoolStep {
    const self = b.allocator.create(LibtoolStep) catch @panic("OOM");

    if (opts.extract_objects) {
        const repack_dir = extractObjects(b, opts.name, opts.sources);
        const output = repackObjects(b, opts.name, opts.out_name, repack_dir);

        self.* = .{
            .step = output.generated.file.step,
            .output = output,
        };

        return self;
    } else {
        const run_step = RunStep.create(b, b.fmt("libtool {s}", .{opts.name}));
        run_step.addArgs(&.{ "xcrun", "libtool", "-static", "-o" });
        const output = run_step.addOutputFileArg(opts.out_name);
        for (opts.sources) |source| run_step.addFileArg(source);

        self.* = .{
            .step = &run_step.step,
            .output = output,
        };

        return self;
    }
}

fn extractObjects(b: *std.Build, name: []const u8, sources: []LazyPath) LazyPath {
    const script = b.addWriteFiles().add(
        b.fmt("extract-{s}.sh", .{name}),
        \\
        \\set -eu
        \\out_dir="$1"
        \\shift
        \\rm -rf "$out_dir"
        \\mkdir -p "$out_dir"
        \\root_dir="$PWD"
        \\cd "$out_dir"
        \\for archive in "$@"; do
        \\    case "$archive" in
        \\        /*) ;;
        \\        *) archive="$root_dir/$archive" ;;
        \\    esac
        \\    xcrun ar -x "$archive"
        \\done
        \\chmod u+rw ./*.o
        \\
    );

    const run_step = RunStep.create(b, b.fmt("extract libtool objects {s}", .{name}));
    run_step.addArgs(&.{ "sh" });
    run_step.addFileArg(script);
    const output = run_step.addOutputDirectoryArg(b.fmt("{s}-objects", .{name}));
    for (sources) |source| run_step.addFileArg(source);

    return output;
}

fn repackObjects(b: *std.Build, name: []const u8, out_name: []const u8, objects: LazyPath) LazyPath {
    const script = b.addWriteFiles().add(
        b.fmt("repack-{s}.sh", .{name}),
        \\
        \\set -eu
        \\out_file="$1"
        \\object_dir="$2"
        \\xcrun libtool -static -o "$out_file" "$object_dir"/*.o
        \\xcrun ranlib "$out_file"
        \\
    );

    const run_step = RunStep.create(b, b.fmt("libtool repack {s}", .{name}));
    run_step.addArgs(&.{ "sh" });
    run_step.addFileArg(script);
    const output = run_step.addOutputFileArg(out_name);
    run_step.addDirectoryArg(objects);

    return output;
}
