import { dlopen, FFIType, JSCallback, toArrayBuffer, type Pointer } from "bun:ffi";
import { defineStruct, type StructDef } from "bun-ffi-structs";
import { EventEmitter } from "node:events";
import { resolve } from "node:path";

export enum EventType {
    TestData = 1,
}

export const TestDataStruct = defineStruct([
    ["id", "u64"],
    ["allocated", "pointer"],
]);

const eventStructs: Record<EventType, StructDef<any>> = {
    [EventType.TestData]: TestDataStruct,
};

export type EventDataMap = {
    [EventType.TestData]: ReturnType<typeof TestDataStruct.unpack>;
};

function getCoreLib() {
    const symbols = dlopen(
        resolve(import.meta.dir, "../../zig-out/lib/libcore.dylib"),
        {
            initState: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            pollEvents: {
                args: [],
                returns: FFIType.void,
            },
            startLoop: {
                args: [],
                returns: FFIType.void,
            },
            createSettings: {
                args: [],
                returns: FFIType.pointer,
            },
            destroySettings: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            createIo: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyIo: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            createMonitor: {
                args: [],
                returns: FFIType.pointer,
            },
            destroyMonitor: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
            destroyAllocated: {
                args: [FFIType.pointer],
                returns: FFIType.void,
            },
        },
    );

    return symbols;
}

export class Core {
    private lib: ReturnType<typeof getCoreLib>;
    private jsCallback: JSCallback | null = null;
    private _nativeEvents: EventEmitter = new EventEmitter();

    get nativeEvents(): EventEmitter {
        return this._nativeEvents;
    }

    constructor() {
        this.lib = getCoreLib();
    }

    initState(): void {
        const emitter = this._nativeEvents;
        this.jsCallback = new JSCallback(
            function handleEvent(event: number, dataPtr: Pointer, dataLen: number): void {
                const eventType = event as EventType;
                const structDef = eventStructs[eventType];
                if (structDef) {
                    emitter.emit(eventType.toString(), structDef.unpack(toArrayBuffer(dataPtr, 0, Number(dataLen))));
                }
            },
            {
                args: [FFIType.u8, FFIType.pointer, FFIType.u64],
                returns: FFIType.void,
            },
        );
        this.lib.symbols.initState(this.jsCallback.ptr);
    }

    pollEvents(): void {
        this.lib.symbols.pollEvents();
    }

    startLoop(): void {
        this.lib.symbols.startLoop();
    }

    createSettings(): Pointer | null {
        return this.lib.symbols.createSettings() as Pointer | null;
    }

    destroySettings(handle: Pointer): void {
        this.lib.symbols.destroySettings(handle);
    }

    createIo(): Pointer | null {
        return this.lib.symbols.createIo() as Pointer | null;
    }

    destroyIo(handle: Pointer): void {
        this.lib.symbols.destroyIo(handle);
    }

    createMonitor(): Pointer | null {
        return this.lib.symbols.createMonitor() as Pointer | null;
    }

    destroyMonitor(handle: Pointer): void {
        this.lib.symbols.destroyMonitor(handle);
    }

    destroyAllocated(handle: number | bigint): void {
        this.lib.symbols.destroyAllocated(handle as Pointer);
    }
}
