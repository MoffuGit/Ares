import { render, useKeydown } from "@ares/tui-solid";
import { AppContext, useSettings, useTheme } from "@ares/shared/solid";
import { TuiApp } from "./app.ts";
import { resolve } from "path";
import {
    Sidebar,
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarInset,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarProvider,
    SidebarTrigger,
} from "./components/sidebar.tsx";

const settingsPath = resolve(import.meta.dir, "../../../../settings");
const bizApp = new TuiApp(settingsPath);
bizApp.start();

function Line(props: { children: any }) {
    return (
        <box width={{ percent: 100 }} height={{ point: 1 }}>
            {props.children}
        </box>
    );
}

function App() {
    const settings = useSettings();
    const theme = useTheme();

    useKeydown((event) => {
        const data = event.data as { codepoint: number; mods: number };
        if (data.codepoint === 99 && (data.mods & 4) !== 0) {
            bizApp.stop();
            process.exit(0);
        }
    });

    return (
        <SidebarProvider>
            <Sidebar>
                <SidebarHeader>
                    <box height={{ point: 1 }}>Ares</box>
                </SidebarHeader>
                <SidebarContent>
                    <SidebarGroup>
                        <SidebarGroupLabel>Theme</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>scheme: {settings()?.scheme ?? "loading..."}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>light: {settings()?.light_theme ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>dark: {settings()?.dark_theme ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>theme: {theme()?.name ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                            </SidebarMenu>
                        </SidebarGroupContent>
                    </SidebarGroup>
                    <SidebarGroup>
                        <SidebarGroupLabel>Colors</SidebarGroupLabel>
                        <SidebarGroupContent>
                            <SidebarMenu>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>fg: {theme()?.fg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>bg: {theme()?.bg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>primaryFg: {theme()?.primaryFg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>primaryBg: {theme()?.primaryBg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>mutedFg: {theme()?.mutedFg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                                <SidebarMenuItem>
                                    <SidebarMenuButton>mutedBg: {theme()?.mutedBg?.join(", ") ?? "—"}</SidebarMenuButton>
                                </SidebarMenuItem>
                            </SidebarMenu>
                        </SidebarGroupContent>
                    </SidebarGroup>
                </SidebarContent>
            </Sidebar>
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

render(() => (
    <AppContext.Provider value={bizApp}>
        <App />
    </AppContext.Provider>
));
