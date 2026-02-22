I think the current structure is really bad,
and i don't know how to add component to the window and update them
I probably should check the existing framework and take ideas from there

─	hh	2500	9472	BOX DRAWINGS LIGHT HORIZONTAL
━	HH	2501	9473	BOX DRAWINGS HEAVY HORIZONTAL
│	vv	2502	9474	BOX DRAWINGS LIGHT VERTICAL
┃	VV	2503	9475	BOX DRAWINGS HEAVY VERTICAL
┄	3-	2504	9476	BOX DRAWINGS LIGHT TRIPLE DASH HORIZONTAL
┅	3_	2505	9477	BOX DRAWINGS HEAVY TRIPLE DASH HORIZONTAL
┆	3!	2506	9478	BOX DRAWINGS LIGHT TRIPLE DASH VERTICAL
┇	3/	2507	9479	BOX DRAWINGS HEAVY TRIPLE DASH VERTICAL
┈	4-	2508	9480	BOX DRAWINGS LIGHT QUADRUPLE DASH HORIZONTAL
┉	4_	2509	9481	BOX DRAWINGS HEAVY QUADRUPLE DASH HORIZONTAL
┊	4!	250A	9482	BOX DRAWINGS LIGHT QUADRUPLE DASH VERTICAL
┋	4/	250B	9483	BOX DRAWINGS HEAVY QUADRUPLE DASH VERTICAL
┌	dr	250C	9484	BOX DRAWINGS LIGHT DOWN AND RIGHT
┍	dR	250D	9485	BOX DRAWINGS DOWN LIGHT AND RIGHT HEAVY
┎	Dr	250E	9486	BOX DRAWINGS DOWN HEAVY AND RIGHT LIGHT
┏	DR	250F	9487	BOX DRAWINGS HEAVY DOWN AND RIGHT
┐	dl	2510	9488	BOX DRAWINGS LIGHT DOWN AND LEFT
┑	dL	2511	9489	BOX DRAWINGS DOWN LIGHT AND LEFT HEAVY
┒	Dl	2512	9490	BOX DRAWINGS DOWN HEAVY AND LEFT LIGHT
┓	LD	2513	9491	BOX DRAWINGS HEAVY DOWN AND LEFT
└	ur	2514	9492	BOX DRAWINGS LIGHT UP AND RIGHT
┕	uR	2515	9493	BOX DRAWINGS UP LIGHT AND RIGHT HEAVY
┖	Ur	2516	9494	BOX DRAWINGS UP HEAVY AND RIGHT LIGHT
┗	UR	2517	9495	BOX DRAWINGS HEAVY UP AND RIGHT
┘	ul	2518	9496	BOX DRAWINGS LIGHT UP AND LEFT
┙	uL	2519	9497	BOX DRAWINGS UP LIGHT AND LEFT HEAVY
┚	Ul	251A	9498	BOX DRAWINGS UP HEAVY AND LEFT LIGHT
┛	UL	251B	9499	BOX DRAWINGS HEAVY UP AND LEFT
├	vr	251C	9500	BOX DRAWINGS LIGHT VERTICAL AND RIGHT
┝	vR	251D	9501	BOX DRAWINGS VERTICAL LIGHT AND RIGHT HEAVY
┠	Vr	2520	9504	BOX DRAWINGS VERTICAL HEAVY AND RIGHT LIGHT
┣	VR	2523	9507	BOX DRAWINGS HEAVY VERTICAL AND RIGHT
┤	vl	2524	9508	BOX DRAWINGS LIGHT VERTICAL AND LEFT
┥	vL	2525	9509	BOX DRAWINGS VERTICAL LIGHT AND LEFT HEAVY
┨	Vl	2528	9512	BOX DRAWINGS VERTICAL HEAVY AND LEFT LIGHT
┫	VL	252B	9515	BOX DRAWINGS HEAVY VERTICAL AND LEFT
┬	dh	252C	9516	BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
┯	dH	252F	9519	BOX DRAWINGS DOWN LIGHT AND HORIZONTAL HEAVY
┰	Dh	2530	9520	BOX DRAWINGS DOWN HEAVY AND HORIZONTAL LIGHT
┳	DH	2533	9523	BOX DRAWINGS HEAVY DOWN AND HORIZONTAL
┴	uh	2534	9524	BOX DRAWINGS LIGHT UP AND HORIZONTAL
┷	uH	2537	9527	BOX DRAWINGS UP LIGHT AND HORIZONTAL HEAVY
┸	Uh	2538	9528	BOX DRAWINGS UP HEAVY AND HORIZONTAL LIGHT
┻	UH	253B	9531	BOX DRAWINGS HEAVY UP AND HORIZONTAL
┼	vh	253C	9532	BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
┿	vH	253F	9535	BOX DRAWINGS VERTICAL LIGHT AND HORIZONTAL HEAVY
╂	Vh	2542	9538	BOX DRAWINGS VERTICAL HEAVY AND HORIZONTAL LIGHT
╋	VH	254B	9547	BOX DRAWINGS HEAVY VERTICAL AND HORIZONTAL

*   Upper Half Block (U+2580): ▀

*   Lower Half Block (U+2584): ▄

*   Left Half Block (U+258C): ▌

*   Right Half Block (U+2590): ▐

Lower one eighth ▁
lower one quarter ▂
lower three eighths ▃
lower half ▄
lower five eigth ▅
lower three quarter ▆
lower seven eighth ▇
full block █

upper one eight ▔
upper one quarter 🮂
upper three eights 🮃
upper half ▀
upper five eight 🮄
upper three quarter 🮅
upper sevne eight block 🮆
▄▖
 ▌
left one eight ▏
left one quarter ▎
left three eighths ▍
left half block ▌
left five eighth ▋
left three quarter ▊
left seven eighths ▉

right one eight ▕
right one quarter 🮇
right three eighths 🮈
right half block ▐
right five eighth 🮉
right three quarter 🮊
right seven eighths 🮋
🯦
🯧
𜺯
🯦
┃
▮
╹

part that can have more style could be the lsp status view
or the undo tree,

vertyical bars
❘❙❚

I need to test how to handle the memory between the typescript and zig side,
I'm going to follow a similart approach to the one that used for xcode,
one detail that I'm not sure how it work is the backend side of electrobun,
i need to check where is the main loop of this side of the application
and how to communicate between the zig side, the backend side and the front side,

for example, for the filetree i need a way for creating the worktree and notify the events
that get generated in this side to the backend part of electrobun and then passing this events to the
front end and updating the view?, yeah, but I'm not sure how any of this would work on typescript and the
electrobun architecture, once that is done, making the filetree is not really that hard

i read the colab project and have a similar process to mine, they have their electrobun project and a small zig project,
they compile the zig project and run it with a bun spawn(probably another thread?), and they communicate between the two,
i need something similar to that, i should search for more examples of this

i can follow how ghostty architects the C ABI lib for the macOS application,
for that i would break apart my zig system, between the App things ans the TUI things,
the TUI things would be all the Window, Renderer, TTY, Elements things
and the App things would be the Worktree, Resolver, Buffers, Settings
that way i can have the App system as a common point between the desktop app and the tui,

Not all the events that happen on the two sided should get handled by the App, only the events
that require this common point, for example, the mouse clicks and focus changes should not pass
to the app, but key press events should, they would get handled by the resolver, if they dont get consumed they can propagate
to the ui, but if they get consumed they create an event, this events can get send to the ui or not, that's going to depend on what they do,
this it's going to be interesting at least, I'm not sure on how to pull it off but that ok,
it's going to be fun

mmmmmmmmmmmm
i don't know what belong where, what should i share,
i kinda know what should not share,
Window, Renderer, TTY, Screen
this are terminal specific,
Workspace not really but Project yes,
from project i need the Worktree and the BufferStore,
well, i dont really need the Project but the structures inside it,
it looks like with FFI you can pass function from ts to zig
if this is true i can follow the same pattern that ghostty uses (pass a callback)

Before writing more things i need to think about the Architecture
of my application and what are the different pieces that an
Editor needs, lets call it "business logic"
lets write what parts i consider business logic

First it would be the Project,
the project has a BufferStore
and a worktree
then it would be the configuration

that's what i consider to be the business logic (in the future it would grow[lsp, git, tressitter])

Our App it should be an structure
that hold the business logic:
it should contain a set of Projects
this project should contain a Worktree (or many)
and a BufferStore (Current State of the Files)
This should contain a configuration

this are the parts that are share between the two Applications
from there, the others parts are UI or Plataform specific
(Screen, Window, TTY, Renderer, Elements, Workspace, Tabs...)

There are other parts that could get shared between the
two App, this could be the Resolver, but for now that all
