the zig project it's going to get used by the desktop app(electrobun) and
for the cli app (opentui)

the bus needs to take the prop event, convert it to an AnyEvent
and add it to the mailbox

The monitor it's not going to live on the CoreLib,
you need to create it as part of you application,
you need to destroy it as well once you are done with it,
the same for the settings and the io

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
