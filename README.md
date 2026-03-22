fsevents -> mac specific, used for watching directories without creating way to many fd

the metal view works and i think this will be the path for the editor and terminal views,
we need to improve the structure of the library and update the messages we send between the zig side and the bun side
the ts side dont need the buffer updates anymore because they dont need the state nor the bytes,
but i need to setup a correct representation of the gpu view between the ts and zig sides,
they need to know what view are we showing (editor, terminal), what the state of it (is healthy or broken or is getting removed)
they need to know the size of it,
on the future, the buffers will have more data, not only the file data, things like lsp errors and undo changes and more things,
the ts will require that info (maybe) but for now i can remove the buffer from the ts side
what i need to add is a correct and good representation of the html surface on the zig side,
i can copy parts of what i have at the swift version of my app, and update it to the new app,
the cool part is that this changes are really simple, the CAPI was really small and the surface function where only 3 or 4
and this surfaces where thinked to represent metal views

after that we should write the representation of a View on the ts side and the zig side,
and adding the functions that the ts side needs to call for updating the zig views,

once that done i can add the creation of them on the ts side and updating them in base of user interaction
