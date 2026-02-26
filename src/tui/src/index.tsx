import { createCliRenderer, TextAttributes } from "@opentui/core";
import { createRoot } from "@opentui/react";
// import { dlopen } from "bun:ffi";
// import { resolve } from "node:path";
//
// const libPath = resolve(import.meta.dir, "../../../zig-out/lib/libcore.dylib");
// const aresLib = dlopen(libPath, {
//     init_state: {
//         args: [],
//         returns: "void"
//     }
// });

function App() {
    // aresLib.symbols.init_state()
    return (
        <box alignItems="center" justifyContent="center" flexGrow={1}>
            <box justifyContent="center" alignItems="flex-end">
                <ascii-font font="tiny" text="OpenTUI" />
                <text attributes={TextAttributes.DIM}>What will you build?</text>
            </box>
        </box>
    );
}

const renderer = await createCliRenderer();
createRoot(renderer).render(<App />);
