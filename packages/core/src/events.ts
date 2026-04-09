import { type StructDef } from "bun-ffi-structs";
import { EditorState, KeymapMatch, ModeUpdate, SurfaceState } from "./structs";

export enum EventType {
    SettingsUpdate,
    ThemeUpdate,
    FiletreeUpdate,
    SurfaceUpdate,
    EditorUpdate,
    ModeUpdate,
    KeymapMatch,
}

export const EventsName: Record<EventType, string> = {
    [EventType.FiletreeUpdate]: "FiletreeUpdate",
    [EventType.SettingsUpdate]: "SettingsUpdate",
    [EventType.ThemeUpdate]: "ThemeUpdate",
    [EventType.EditorUpdate]: "EditorUpdate",
    [EventType.SurfaceUpdate]: "SurfaceUpdate",
    [EventType.ModeUpdate]: "ModeUpdate",
    [EventType.KeymapMatch]: "KeymapMatch",
};

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.SettingsUpdate]: null,
    [EventType.ThemeUpdate]: null,
    [EventType.FiletreeUpdate]: null,
    [EventType.SurfaceUpdate]: SurfaceState,
    [EventType.EditorUpdate]: EditorState,
    [EventType.ModeUpdate]: ModeUpdate,
    [EventType.KeymapMatch]: KeymapMatch,
};
