const Snapshot = @This();

//snapshot dont store any allocator,
//every operation should pass the allocator
//that want to use,
//
//for example, when adding entries the ideal is to use an
//arena allocator, when creating the Maps or b trees we should use
//an gpa, why, because Snapshot can be cloned,
//entries can stay alive all the time they want,
//but the maps and trees are going to be changing in base of the events
