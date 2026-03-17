import { render, useKeydown } from "@ares/tui-solid";
import { AppContext } from "@ares/shared/solid";
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


function Line(props: { children: any }) {
    return (
        <box width={{ percent: 100 }} height={{ point: 1 }}>
            {props.children}
        </box>
    );
}

function App() {
    useKeydown((event) => {
        const data = event.data as { codepoint: number; mods: number };
        if (data.codepoint === 99 && (data.mods & 4) !== 0) {
            shutdown();
            process.exit(0);
        }
    });

    return (
        <SidebarProvider>
            <AppSidebar />
            <SidebarInset>
                <box flexDirection="row" height={{ point: 1 }}>
                    <SidebarTrigger />
                </box>
                <box flexDirection="column" flexGrow={1} padding={{ all: { point: 1 } }}>
                    <Line>Main content area</Line>
                </box>
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
