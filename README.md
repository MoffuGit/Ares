Three things are on top right now

Tui
now that i think about it the mutations
happen on a different thread to the app Loop thread,
meaning, the draw happens on a different thread to where we apply our mutations,
what options we have?

protecting the window with a mutex,
applying the mutations inside the Loop,

what's our process?

the tty send his events to the loop,
the loop drains them, resolve them and send the correct
event to our bus, we take that events, send them to our elements,
our elements update their values if they need, we send our mutations
the mutatins update the tree then we draw,

the loop is not needed anymore,
the ts side controls the main loop,
we call mailbox.drain from ts,
we receive the events and update our elements
we send our updates,
we apply them,
we draw,

repeat,

we dont need any mutex for this and is more natural this way

Appearance Observer
we need to add a delegate class to the NSDistributedNotificationCenter
and call our block, this will let us notify our application that the apperance changed,
meaning, updating the loaded theme,

Read Settings
i fucked up this part, the read of the settings is naive and wrong,
i need to protect my settings (they get updated and read it on different theads)
and the strings probably should be part of an arena allocator,
its the most easier way to not access deallocated memory,
