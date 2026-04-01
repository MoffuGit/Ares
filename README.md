on the tui, i need to do the next things

the ts elements require to know their computed rect,

for the terminal, I'm reading the ghostling code and Termio from ghostty
This is a system that work in conjuction with the ghostty vt library
once i can get my screen result from this system i can write it into my shared state
and then render it into my metal view, it's really basic but it's going to help me to structure
my project.

something i want to have is having the option to start a terminal that is not like link to a project,
i think that can be a cool behavoir, you start with a terminal, then you choose to go to a x project,
then you could set a keymap that creates or open a project at that pwd,
that can be interesting, you load or open the project into the list of project and then you can start creating more
views, then, if you feel like it you can open another project and the start jumping between them, all from the same window
yeah, i kinda like that,

once that done, start working on text editing
i will use a gap buffer,
i think for that it would better to start impl the cursor
and cursor position things, and once that done, start workign on editing text,

other things that i need to do
First i want to add a terminal (ghostty-vt)
app state storage
adding the fsevents for watching the files,
adding keymaps for moving the focus
adding keymaps for the filetree(moving around with h,j,k,l),
adding more capabilites to the filetree(move, create, rename and delete file/s and directory/ies)
a filetree but more on the oil style
git integration
split views
then  i will start working on a syntax highlighter
once i have that i would like to work on an lsp
a canvas
things like search(files or words),
and more...
