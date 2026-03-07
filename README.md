Three things are on top right now

testing the Mutations,
the parser is already tested, and the element tree as well,
we should test that the Commands produce the expected tree,
and that update the correct elements,

Appearance Observer
we need to add a delegate class to the NSDistributedNotificationCenter
and call our block, this will let us notify our application that the apperance changed,
meaning, updating the loaded theme,

Read Settings
i fucked up this part, the read of the settings is naive and wrong,
i need to protect my settings (they get updated and read it on different theads)
and the strings probably should be part of an arena allocator,
its the most easier way to not access deallocated memory,
