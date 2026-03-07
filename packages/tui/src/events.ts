import { type StructDef } from "bun-ffi-structs";
import { KeyEvent, MouseEvent, Resize, Scheme } from "./structs";

export enum EventType {
    KeyDown,
    KeyUp,
    MouseDown,
    MouseUp,
    MouseMove,
    Click,
    MouseEnter,
    MouseLeave,
    Wheel,
    Focus,
    Blur,
    Resize,
    Scheme,
}

export const Events: Record<EventType, StructDef<any> | null> = {
    [EventType.KeyDown]: KeyEvent,
    [EventType.KeyUp]: KeyEvent,
    [EventType.MouseDown]: MouseEvent,
    [EventType.MouseUp]: MouseEvent,
    [EventType.MouseMove]: MouseEvent,
    [EventType.Click]: MouseEvent,
    [EventType.MouseEnter]: MouseEvent,
    [EventType.MouseLeave]: MouseEvent,
    [EventType.Wheel]: MouseEvent,
    [EventType.Focus]: null,
    [EventType.Blur]: null,
    [EventType.Resize]: Resize,
    [EventType.Scheme]: Scheme,
};
