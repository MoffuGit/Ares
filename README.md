debug(events_thread): starting read thread
                                          FATAL ERROR: Buffer size (6) is smaller than struct size (16) for unpacking.
                                                                                                                      1 | // src/structs_ffi.ts
             2 | import { ptr, toArrayBuffer } from "bun:ffi";
                                                              3 | function fatalError(...args) {
                                                                                                4 |   const message = args.join(" ");
   5 |   console.error("FATAL ERROR:", message);
                                                6 |   throw new Error(message);
                                                                                                            ^
                                                                                                             error: Buffer size (6) is smaller than struct size (16) for unpacking.
                                                       at fatalError (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/node_modules/.bun/bun-ffi-structs@0.1.2+1fb4c65d43e298b9/node_modules/bun-ffi-structs/index.js:6:26)
                                                                                                   at unpack (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/node_modules/.bun/bun-ffi-structs@0.1.2+1fb4c65d43e298b9/node_modules/bun-ffi-structs/index.js:551:9)
          at handleEvent (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/packages/tui/core/src/index.ts:139:43)
                                                                                                                           at drainMailbox (libtui.dylib) (builtin://bun/ffi:3:15)
                                                      at drainMailbox (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/packages/tui/core/src/index.ts:209:26)
                                      at tick (/Volumes/Home_SSD/Users/home/Documents/projects/Ares/packages/tui/core/src/app.ts:99:18)
