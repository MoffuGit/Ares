the zig project it's going to get used by the desktop app(electrobun) and
for the cli app (opentui)

if the watcher gets and event we need to read again the settings or the theme files,
once that's done, we need to notify our bus, right now i dont have any zig piece that needs
the settings data

the resolver it needs to have some part on zig and other parts on ts,
or maybe on wasm?, or maybe i should recreate the structure from the zig side to a structure on ts
or maybe all happens on the zig side and ts only send and receive events?
