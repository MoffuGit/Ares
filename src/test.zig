const App = @import("app.zig");
const chunk_pool = @import("chunk_pool.zig");
const chunked_path = @import("chunked_path.zig");
const datastruct = @import("datastruct.zig");
const entity = @import("entity.zig");
const Loop = @import("loop.zig");
const Project = @import("project.zig");
const WorktreeStore = @import("project/worktree_store.zig");
const scheduler = @import("scheduler.zig");
const Session = @import("session.zig");
const subscription = @import("subscription.zig");
const tasks = @import("tasks.zig");
const Workspace = @import("workspace.zig");
const Worktree = @import("worktree.zig");

test {
    _ = App;
    _ = chunk_pool;
    _ = chunked_path;
    _ = datastruct;
    _ = entity;
    _ = Loop;
    _ = scheduler;
    _ = Project;
    _ = WorktreeStore;
    _ = Session;
    _ = subscription;
    _ = tasks;
    _ = Workspace;
    _ = Worktree;
}
