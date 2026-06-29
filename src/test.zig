const App = @import("app.zig");
const datastruct = @import("datastruct.zig");
const entity = @import("entity.zig");
const scheduler = @import("scheduler.zig");
const loop = @import("loop.zig");
const subscription = @import("subscription.zig");
const Worktree = @import("worktree.zig");
const tasks = @import("tasks.zig");

test {
    _ = tasks;
    _ = subscription;
    _ = datastruct;
    _ = entity;
    _ = App;
    _ = Worktree;
    _ = scheduler;
    _ = loop;
}
