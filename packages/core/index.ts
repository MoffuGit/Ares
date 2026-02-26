import { dlopen, FFIType, type Pointer } from "bun:ffi";
import { resolve } from "node:path";

const { symbols } = dlopen(
    resolve(import.meta.dir, "../../zig-out/lib/libcore.dylib"),
    {
        initState: {
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
    },
);

export type SettingsHandle = Pointer;
export type IoHandle = Pointer;
export type MonitorHandle = Pointer;

export function initState() {
    symbols.initState();
}

export function createSettings(): SettingsHandle | null {
    return symbols.createSettings() as Pointer | null;
}

export function destroySettings(handle: SettingsHandle): void {
    symbols.destroySettings(handle);
}

export function createIo(): IoHandle | null {
    return symbols.createIo() as Pointer | null;
}

export function destroyIo(handle: IoHandle): void {
    symbols.destroyIo(handle);
}

export function createMonitor(): MonitorHandle | null {
    return symbols.createMonitor() as Pointer | null;
}

export function destroyMonitor(handle: MonitorHandle): void {
    symbols.destroyMonitor(handle);
}
