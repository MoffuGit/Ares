const Worktree = @This();
//WARN:
//the idea of this is to wakeup the scanner thread only when needed,
//and the same for the monitor,
//this two threads can speak one with each other
//but only the scanner can update the worktree
//
//scanner: Scanner
//scanner_thread: Thread
//
//monitor: Monitor,
//monitor_thread: Thread
//
