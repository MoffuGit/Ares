the zig project it's going to get used by the desktop app(electrobun) and
for the cli app (opentui)

the bus needs to take the prop event, convert it to an AnyEvent
and add it to the mailbox

The monitor it's not going to live on the CoreLib,
you need to create it as part of you application,
you need to destroy it as well once you are done with it,
the same for the settings,
