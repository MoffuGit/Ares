fsevents -> mac specific, used for watching directories without creating way to many fd

i need to make an aggreament between the zig side and the ts side,
if i go basic we would have two rendered views,
the editor and the terminal,
the ts side create his Component,
the ts side do what i needs to do, that can be anything right now,
but what is clear should happen is that when the tag finish the load it should send an rpc messge with the tag id, the rect, the kind of view and the data for that view,
that then gets send to the zig side, the zig side then create the renderer, load the data it needs etc,
once that's done there should be an aggrement between the ts side and the zig side about what events and calls can happen on X type of view,

the react side create their components (editor, terminal), and then they load the wgpu tag,
when that happnes they send a message with the followin:

tag id
kind
data

the bun side receive this msg and do the followin:
it go to the project and ask him to create a new view with the kind and data received from the rpc,
and it passed the surface pointer to this view, the project can store them on two different arrays,
one for editors and another for terminals, this structure it will have his own zig representation,
this views maybe or maybe not share code but they have specific logic and functions,
this functions exist on the ts side as well, the rpc can send events from the webview to this views
but they need to be differenced with something, the id can work, maybe i dont store the ts views on arrays but on maps,

once that done i can add the creation of them on the ts side and updating them in base of user interaction
