import { defineStruct, type StructDef } from "bun-ffi-structs";

export enum EventType {
    SettingsUpdate,
    ThemeUpdate,
    FiletreeUpdate,
    BufferUpdate,
}

export const EventsName: Record<EventType, string> = {
    [EventType.FiletreeUpdate]: "FiletreeUpdate",
    [EventType.SettingsUpdate]: "SettingsUpdate",
    [EventType.ThemeUpdate]: "ThemeUpdate",
    [EventType.BufferUpdate]: "BufferUpdate",
};

const BufferUpdateEvent = defineStruct([
    ["entry_id", "u64"],
] as const);

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.SettingsUpdate]: null,
    [EventType.ThemeUpdate]: null,
    [EventType.FiletreeUpdate]: null,
    [EventType.BufferUpdate]: BufferUpdateEvent,
};
