I kinda finish the basic renderer,
the next step is adding scrollin,
once that's done i can start working on text editing
i will use a gap buffer,
i think for that it would better to start impl the cursor
and cursor position things, and once that done, start workign on editing text,

once i have that i think i can start working on the tui,
Right know i dont really want to worry about writing the editor logic as reusable for the tui
because updating it is not really hard, in some ways the code i write for the desktop app could be consider overkill
for a tui, but yeah, once i have the scroll, cursor and text editing done for the desktop app
i will start working on the tui, when i finish the tui, i will start working on a syntax highlighter
once i have that i would like to work on an lsp and once i have all that done i would like to add
a terminal to the desktop app, i dont think i will do that for the tui because i dont really use my terminal text editor that way
for what i know, adding the terminal to the desktop app is not that hard, at the end my rendering system is a copy of the one used for ghostty
and the terminal will use lib-ghostty, but who knows, maybe is really hard


other things that i need to do
adding the fsevents for watching the files,
adding keymaps for moving the focus
adding keymaps for the filetree(moving around with h,j,k,l),
adding more capabilites to the filetree(move, create, rename and delete file/s and directory/ies)
a filetree but more on the oil style
split views
canvas of views,
things like search(files or words),
and more...

