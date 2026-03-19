i think using zustand will help a lot for the desktop app,
lets follow the next approach,
CoreApp becomes a EventEmitter, we revome the event emitter form the webview
and we add zustand, the desktop app parts consume our zustand store,
the tui solid parts uses our solid bindings
the desktop side can send batched events to the webview

the BaseApp is not doing that much for me, either way need to defien my rpc fucntions
and the zustand functions and yeah, i will remove that part
