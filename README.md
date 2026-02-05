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

                            debug(worktree_monitor): monitor added watcher: '/Volumes/Home_SSD/Users/home/Documents/projects/ares/.zig-cache/o/ce021f963debc4d0259e01f4aedd6c60' id=2368                                                                                                                                                                                     debug(worktree_monitor): monitor added watcher: '/Volumes/Home_SSD/Users/home/Documents/projects/ares/.zig-cache/o/de7ab77b7d124072fcbf16276b7b6b09' id=2369                                                                                                                                                                                     debug(worktree_monitor): monitor added watcher: '/Volumes/Home_SSD/Users/home/Documents/projects/ares/.zig-cache/o/6d1bcbe34af4ac66462b52e12dd33fbb' id=2370                                                                                                                                                                                     thread 2481085 panic: reached unreachable code                                                                                                                                                                                     /opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/debug.zig:559:14: 0x1041b955f in assert (ares)                                                                                                                                                                                         if (!ok) unreachable; // assertion failure                                                                                                                                                                                                  ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/.cache/zig/p/libxev-0.0.0-86vtc2-pFAD09Lq7ShCbgupFNVaErAJgtUeS6ahACf2J/src/queue.zig:24:19: 0x1042651b7 in push (ares)                                                                                                                                                                                                 assert(v.next == null);                                                                                                                                                                                                       ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/.cache/zig/p/libxev-0.0.0-86vtc2-pFAD09Lq7ShCbgupFNVaErAJgtUeS6ahACf2J/src/backend/kqueue.zig:264:38: 0x104262c5b in submit (ares)                                                                                                                                                                                                     self.completions.push(c);                                                                                                                                                                                                                          ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/.cache/zig/p/libxev-0.0.0-86vtc2-pFAD09Lq7ShCbgupFNVaErAJgtUeS6ahACf2J/src/backend/kqueue.zig:352:24: 0x104266b87 in tick (ares)                                                                                                                                                                                             try self.submit();                                                                                                                                                                                                            ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/.cache/zig/p/libxev-0.0.0-86vtc2-pFAD09Lq7ShCbgupFNVaErAJgtUeS6ahACf2J/src/backend/kqueue.zig:303:62: 0x10426827b in run (ares)                                                                                                                                                                                                 .until_done => while (!self.done()) try self.tick(1),                                                                                                                                                                                                                                                  ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/Documents/projects/ares/src/worktree/monitor/Thread.zig:94:26: 0x1042aae17 in threadMain_ (ares)                                                                                                                                                                                         _ = try self.loop.run(.until_done);                                                                                                                                                                                                              ^                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/Documents/projects/ares/src/worktree/monitor/Thread.zig:79:21: 0x104288e0b in threadMain (ares)                                                                                                                                                                                         self.threadMain_() catch |err| {                                                                                                                                                                                                         ^                                                                                                                                                                                     /opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/Thread.zig:509:13: 0x1042777bf in callFn__anon_28001 (ares)                                                                                                                                                                                                 @call(.auto, f, args);                                                                                                                                                                                                 ^                                                                                                                                                                                     /opt/homebrew/Cellar/zig/0.15.2/lib/zig/std/Thread.zig:781:30: 0x1042611bb in entryFn (ares)                                                                                                                                                                                                     return callFn(f, args_ptr.*);                                                                                                                                                                                                                  ^                                                                                                                                                                                     ???:?:?: 0x188799c07 in ??? (libsystem_pthread.dylib)                                                                                                                                                                                     ???:?:?: 0x188794ba7 in ??? (libsystem_pthread.dylib)                                                                                                                                                                                     run                                                                                                                                                                                     └─ run exe ares failure                                                                                                                                                                                     error: the following command terminated unexpectedly:                                                                                                                                                                                     /Volumes/Home_SSD/Users/home/Documents/projects/ares/zig-out/bin/ares
                                                                                                                                                                                     Build Summary: 10/12 steps succeeded; 1 failed                                                                                                                                                                                     run transitive failure                                                                                                                                                                                     └─ run exe ares failure
                                                                                                                                                                                     error: the following build command failed with exit code 1:                                                                                                                                                                                     .zig-cache/o/14a0915cdec6ea5d4f6dbc9f98955501/build /opt/homebrew/Cellar/zig/0.15.2/bin/zig /opt/homebrew/Cellar/zig/0.15.2/lib/zig /Volumes/Home_SSD/Users/home/Documents/projects/ares .zig-cache /Volumes/Home_SSD/Users/home/.cache/zig --seed 0x1342af1a -Z9c489a8c96994880 run
