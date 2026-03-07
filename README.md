Three things are on top right now

this can be done with amp
adding a loop should not be hard
and i can provide a reference

the ts side its going to own the loop now,
the part that was giving me problems when thinking
is was how the animation would work with the drainMailbox call,
now i know, the ts animations receive delta updated from the ts loop,
they dont own they own interval nor have a loop on their own,
that means that this loop would always calls drain mailbox, then animation,
or maybe the other way around, but the point is that there are not two loop
calling app draw at any point,
this loop tries to run at a fixed frame speed,
one very frame we can ask for drainMailbox to run,
and do what it needs to do, and then we can call for our animation to
update their progress and data,


this depend on zig objc bindings,
(amp will fuck this up)
this is a manual job
Appearance Observer
we need to add a delegate class to the NSDistributedNotificationCenter
and call our block, this will let us notify our application that the apperance changed,
meaning, updating the loaded theme,
