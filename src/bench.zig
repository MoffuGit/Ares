const std = @import("std");
const prof = @import("prof");

const Context = struct {
    io: std.Io,
};

test "Bench Reads" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{});

    var ctx = Context{
        .io = io,
    };

    const res = try bench.run(Context, &ctx, sleepTest);
    res.log();
}

pub fn sleepTest(_ctx: ?*Context, _: *prof.Profiler) !void {
    const ctx = _ctx.?;

    try ctx.io.sleep(.fromSeconds(1), .real);
}
