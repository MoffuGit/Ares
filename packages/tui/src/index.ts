import { dlopen, FFIType, type Pointer } from "bun:ffi";
import { resolve } from "node:path";

function getTuiLib() {
    const symbols = dlopen(
        resolve(import.meta.dir, "../../../zig-out/lib/libtui.dylib"),
        {},
    );

    return symbols;
}

export class TuiLib {
    private lib: ReturnType<typeof getTuiLib>;

    constructor() {
        this.lib = getTuiLib();
    }
}

let tuiLib: TuiLib | undefined;

export function resolveTuiLib(): TuiLib {
    if (!tuiLib) {
        try {
            tuiLib = new TuiLib();
        } catch (error) {
            throw new Error("Failed to initialize the tui lib");
        }
    }
    return tuiLib;
}
