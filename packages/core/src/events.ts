import { type StructDef } from "bun-ffi-structs";
import { BufferState, KeymapMatch, ModeUpdate } from "./structs";

export enum EventType {
    SettingsUpdate,
    ThemeUpdate,
    FiletreeUpdate,
    BufferUpdate,
    ModeUpdate,
    KeymapMatch,
}

export const EventsName: Record<EventType, string> = {
    [EventType.FiletreeUpdate]: "FiletreeUpdate",
    [EventType.SettingsUpdate]: "SettingsUpdate",
    [EventType.ThemeUpdate]: "ThemeUpdate",
    [EventType.BufferUpdate]: "BufferUpdate",
    [EventType.ModeUpdate]: "ModeUpdate",
    [EventType.KeymapMatch]: "KeymapMatch",
};

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.SettingsUpdate]: null,
    [EventType.ThemeUpdate]: null,
    [EventType.FiletreeUpdate]: null,
    [EventType.BufferUpdate]: BufferState,
    [EventType.ModeUpdate]: ModeUpdate,
    [EventType.KeymapMatch]: KeymapMatch,
};
