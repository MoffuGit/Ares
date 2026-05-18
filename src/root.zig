//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const KiB = 1024;
const MiB = 1024 * KiB;

// pub const prof = @import("odyssey_prof");

/// This is a documentation comment to explain the `printAnotherMessage` function below.
///
/// Accepting an `Io.Writer` instance is a handy way to write reusable code.
pub fn printAnotherMessage(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("Run `zig build test` to run the tests.\n", .{});
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
//
// const ReadContext = struct {
//     io: std.Io,
//     alloc: std.mem.Allocator,
//     path: [:0]const u8,
//     file_size: u64,
// };
// test "Bench Reads 2" {
//     const io = std.testing.io;
//     const gpa = std.testing.allocator;
//
//     const path = "./generated/43564768_1000000_10011.998232663716.json";
//
//     const stat = try std.Io.Dir.cwd().statFile(io, path, .{});
//
//     var ctx: ReadContext = .{
//         .io = io,
//         .alloc = gpa,
//         .path = path,
//         .file_size = stat.size,
//     };
//
//     var benchmark: prof.Benchmark = .init(std.testing.allocator, .{
//         .max_iterations = 100,
//         .max_time_without_new_min_ns = 1000,
//     });
//     defer benchmark.deinit();
//
//     const result = try benchmark.run(ReadContext, &ctx, allocAndTouch);
//
//     if (prof.bench_enabled) {
//         benchmark.log(result);
//         try std.testing.expectEqual(prof.Benchmark.Status.completed, result.status);
//     } else {
//         try std.testing.expectEqual(prof.Benchmark.Status.skipped, result.status);
//     }
// }
//
// fn allocAndTouch(_ctx: ?*ReadContext, _: *prof.Profiler) !void {
//     if (_ctx) |ctx| {
//         const buffer = try ctx.alloc.alloc(u8, 2 * MiB);
//         defer ctx.alloc.free(buffer);
//
//         for (0..(buffer.len + 128 - 1) / 128) |idx| {
//             buffer[idx * 128] = 1;
//         }
//     }
// }
//
// fn allocAndRead(_ctx: ?*ReadContext, _: *prof.Profiler) !void {
//     if (_ctx) |ctx| {
//         const buffer = try ctx.alloc.alloc(u8, 2 * MiB);
//         defer ctx.alloc.free(buffer);
//
//         var file = try std.Io.Dir.cwd().openFile(ctx.io, ctx.path, .{});
//         defer file.close(ctx.io);
//
//         var reader = file.reader(ctx.io, buffer);
//         const interface = &reader.interface;
//
//         while (true) {
//             interface.fill(buffer.len) catch break;
//             interface.tossBuffered();
//         }
//     }
// }
