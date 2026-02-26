the zig project it's going to get used by the desktop app(electrobun) and
for the cli app (opentui)

i need to work on the binding now
how to consume the events from one side and from the other (callbakcs)
how to use the data from one side and te other
how to communicate one side whith the other

lets start handling the settings, this is the easiest part
first i need to update the settings, they should accept a
monitor as a prop, they should watch our settings and theme files
after that we need to check how to consume the settings from typescript
when an update happens what we should do?,
and then we would write our resolver, i prefer writing the resolver on typescript
it's way more easy, of course it would consume the keymap structure, and the tries and all the other things
from zig, it's going to be fast, only that i dont think i need to write the impl on zig,
tomorrow i check it,
