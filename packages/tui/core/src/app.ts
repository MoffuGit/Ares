import type { Pointer } from "bun:ffi";
import { resolveTuiLib, type TuiLib } from ".";
import { Element, createEvent } from "./elements";
import { EventType } from "./events";

export class TuiApp {
    private lib: TuiLib;
    private appPtr: Pointer;
    private windowPtr: Pointer;
    private mutationsPtr: Pointer;
    private timer: Timer | null = null;

    private elementMap: Map<number, Element> = new Map();
    root: Element | null = null;

    constructor() {
        this.lib = resolveTuiLib();

        const app = this.lib.createApp();
        if (!app) throw new Error("Failed to create app");
        this.appPtr = app;

        const window = this.lib.getWindow(app);
        if (!window) throw new Error("Failed to get window");
        this.windowPtr = window;

        const mutations = this.lib.createMutations(this.windowPtr);
        if (!mutations) throw new Error("Failed to create mutations");
        this.mutationsPtr = mutations;

        this.bindEvents();
    }

    private bindEvents(): void {
        const events = this.lib.events;

        const keyEvents = [EventType.KeyDown, EventType.KeyUp] as const;
        const keyNames = ["keydown", "keyup"] as const;

        for (let i = 0; i < keyEvents.length; i++) {
            const name = keyNames[i];
            events.on(keyEvents[i].toString(), (data: unknown, targetId: number) => {
                const target = this.resolveTarget(targetId);
                if (!target) return;
                target.dispatchEvent(createEvent(name, target, data));
            });
        }

        const mouseEvents = [
            EventType.MouseDown, EventType.MouseUp, EventType.MouseMove,
            EventType.Click, EventType.MouseEnter, EventType.MouseLeave, EventType.Wheel,
        ] as const;
        const mouseNames = [
            "mousedown", "mouseup", "mousemove",
            "click", "mouseenter", "mouseleave", "wheel",
        ] as const;

        for (let i = 0; i < mouseEvents.length; i++) {
            const name = mouseNames[i];
            events.on(mouseEvents[i].toString(), (data: unknown, targetId: number) => {
                const target = this.resolveTarget(targetId);
                if (!target) return;
                target.dispatchEvent(createEvent(name, target, data));
            });
        }

        events.on(EventType.Resize.toString(), (data: unknown) => {
            this.root?.dispatchEvent(createEvent("resize", this.root, data));
        });

        events.on(EventType.Focus.toString(), () => {
            this.root?.dispatchEvent(createEvent("focus", this.root!, null));
        });

        events.on(EventType.Blur.toString(), () => {
            this.root?.dispatchEvent(createEvent("blur", this.root!, null));
        });

        events.on(EventType.Scheme.toString(), (data: unknown) => {
            this.root?.dispatchEvent(createEvent("scheme", this.root!, data));
        });
    }

    private resolveTarget(targetId: number): Element | null {
        if (targetId !== 0) return this.elementMap.get(targetId) ?? this.root;
        return this.root;
    }

    registerElement(element: Element): void {
        this.elementMap.set(element.id, element);
    }

    unregisterElement(element: Element): void {
        this.elementMap.delete(element.id);
    }

    setRoot(element: Element): void {
        this.root = element;
        this.registerElement(element);
        element.setAsRoot();
    }

    flush(): void {
        this.lib.processMutations(this.mutationsPtr);
        this.lib.requestDraw(this.appPtr);
        this.lib.drawWindow(this.appPtr);
    }

    tick(): void {
        this.lib.drainMailbox(this.appPtr);
        this.flush();
    }

    start(intervalMs: number = 16): void {
        if (this.timer) return;
        this.timer = setInterval(() => this.tick(), intervalMs);
    }

    stop(): void {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = null;
        }
    }

    destroy(): void {
        this.stop();
        this.lib.destroyMutations(this.mutationsPtr);
        this.lib.destroyApp(this.appPtr);
        this.lib.deinitState();
        this.elementMap.clear();
        this.root = null;
    }
}
