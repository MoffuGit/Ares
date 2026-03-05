the tui has a really bad impl of a MutationQueue,
i didnt like what the model produce, but at least it work as a base,
i need to update the mutation queue and the elements that's mutating,
they worked on the old system,

the desktop is missing a way to know that system apperance it has, for mac i will use
zib-objc and add a notifycation consumer for when this change happens
the tui app dont needs this notifycations, only the desktop app,
this will be part of the core lib, only that the tui would not consume it,
maybe i can skip it when building for tui
