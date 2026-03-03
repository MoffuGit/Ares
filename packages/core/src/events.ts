import { type StructDef } from "bun-ffi-structs";

export enum EventType {
    SettingsUpdate,
    ThemeUpdate,
    WorktreeUpdate,
}

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.SettingsUpdate]: null,
    [EventType.ThemeUpdate]: null,
    [EventType.WorktreeUpdate]: null,
};
