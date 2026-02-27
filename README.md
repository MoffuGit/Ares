the zig project it's going to get used by the desktop app(electrobun) and
for the cli app (opentui)

i need a test file for the zig binding,
they should init the state,
create a monitor, create settings,
load this settings,
destory this settings,
destroy the monitor
deinit the state,
all of this should happen without erros
and without memory leaks

once that's done, we need to start working on the tui,
we need to check what we are going to do with the settings,
we are going to use react, we can probably create a hook
that reads the settings data and create something that we can use
for the ui, yeah, i think that all for now,
before even touching the react part i would like to
check how the communication between the backend and fronend work
on electrobun, i think the tui and the desktop app can share the core lib
but not the react code

the zig library has a global event emitter and a bus
the bus is only for communicating from zig to ts,
the event emitter is for zig communication,
right now i would like to check what messages i would send on the two
the bus has only a setting event, the event emitter has nothing,
what i can think right now is that the bus needs events for,
worktree updated (UpdatedEntriesSet), buffer reads (BufferStore reads)
and the evnet emitter needs the same, worktree updated and buffer reads,
the bus can receive event for any thread and the event emitter
dont really needs to have his own thread, at the end the structures
he communicate with have their own thred to queue some work

i need to work on te resolver as well,
its going to have a lot more parts written on ts and not in zig
it make it easier to work with, i would check when i get here
how much will live on zig and how much on ts
