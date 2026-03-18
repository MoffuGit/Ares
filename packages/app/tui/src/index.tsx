import { render, useKeydown, useScheme } from "@ares/tui-solid";
import { createSignal, createEffect, onCleanup, For } from "solid-js";
import { AppContext, useApp, useMode, useScopedKeymaps } from "@ares/shared/solid";
import { resolve } from "path";
import {
    SidebarInset,
    SidebarProvider,
    SidebarTrigger,
} from "./components/sidebar.tsx";
import { AppSidebar } from "./components/app-sidebar.tsx";
import { CoreApp } from "@ares/shared/core";

const settingsPath = resolve(import.meta.dir, "../../../../settings");
const projectPath = "/Volumes/Home_SSD/Users/home/Documents/projects/ares";
const bizApp = new CoreApp(settingsPath, projectPath, false);
bizApp.start();

setInterval(() => {
    bizApp.drainMailbox()
}, 100)


function Line(props: { children: any }) {
    return (
        <box width={{ percent: 100 }} height={{ point: 1 }}>
            {props.children}
        </box>
    );
}

function EditorContent() {
    const mode = useMode();
    const globalKeymaps = useScopedKeymaps("global");
    const editorKeymaps = useScopedKeymaps("editor");

    return (
        <box flexDirection="column" flexGrow={1} padding={{ all: { point: 1 } }}>
            <Line>Mode: {mode()}</Line>
            <Line>Global Keymaps ({globalKeymaps().length}):</Line>
        </box>
    );
}

function App() {
    const [sidebarOpen, setSidebarOpen] = createSignal(true);

    useScheme((evt) => {
        const scheme = evt.data as { value: number };
        bizApp.setSystemScheme(scheme.value);
    });

    useKeydown((event) => {
        const data = event.data as { codepoint: number; mods: number };
        if (data.codepoint === 99 && (data.mods & 4) !== 0) {
            shutdown();
            process.exit(0);
        }

        bizApp.handleKeyDown(
            data.codepoint,
            {
                shift: (data.mods & 1) !== 0,
                alt: (data.mods & 2) !== 0,
                ctrl: (data.mods & 4) !== 0,
                super: (data.mods & 8) !== 0,
                hyper: false,
                meta: false,
                caps_lock: false,
                num_lock: false,
            },
        );
    });

    const keymaps = useScopedKeymaps("global");

    createEffect(() => {
        const handler = (sequence: string) => {
            const action = keymaps()[sequence];
            if (action === "workspace:toggle_left_sidebar") {
                setSidebarOpen((prev) => !prev);
            }
        };
        bizApp.events.on("keymapSequence", handler);
        onCleanup(() => bizApp.events.off("keymapSequence", handler));
    });

    return (
        <SidebarProvider open={sidebarOpen()} onOpenChange={setSidebarOpen}>
            <AppSidebar />
            <SidebarInset>
                <box flexDirection="row" height={{ point: 1 }}>
                    <SidebarTrigger />
                </box>
                <EditorContent />
            </SidebarInset>
        </SidebarProvider>
    );
}

const { dispose } = render(() => (
    <AppContext.Provider value={bizApp}>
        <App />
    </AppContext.Provider>
));

let stopped = false;
function shutdown() {
    if (stopped) return;
    stopped = true;
    bizApp.stop();
    dispose();
}

process.on("beforeExit", shutdown);
process.on("SIGINT", () => {
    shutdown();
    process.exit(0);
});
process.on("SIGTERM", () => {
    shutdown();
    process.exit(0);
});
