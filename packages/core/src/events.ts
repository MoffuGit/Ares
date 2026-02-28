import { type StructDef } from "bun-ffi-structs";

export enum EventType {
    SettingsUpdate,
    ThemeUpdate
}

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.SettingsUpdate]: null,
    [EventType.ThemeUpdate]: null,
};
