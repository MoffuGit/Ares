for the buffers the zustand its going to store a cache of buffers
the process its going tobe as follows
for many reasons you can try to read a buffer,
this reasons can be that you selected an entry and this changed the view entry
or you are picking or watheve
the point is that when you do that the systems it's going to try to read a buffer
when this happens we need to check on the zustand side if the buffer exists, if it exists
we can simple pass it, if not we send a msg on the rpc that will try to open the buffer and read from it,
once that happnes, the zig side will manage the following, if the buffer exist in there it will send it's data
if not it will try to read from it and send an event, when the core side receive buffers events we can simply send
th eid and the buffer to the rpc and zustand would update the buffer data in base of this update

that way a signle buffer can get share, i would need to add a view next
and tabs and splits, some parts of this can get stores on the zustand store
i want to really check that part because im not sure if i want the clickEntry function on the zustand store or not
