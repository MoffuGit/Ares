import { For } from "solid-js";
import { useApp, useFiletree, useTheme } from "@ares/shared/solid";
import {
    Sidebar,
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "./sidebar.tsx";

function FileTree() {
    const filetree = useFiletree();
    const app = useApp();
    const theme = useTheme();

    return (
        <scrollable mode="vertical" flexGrow={1} width={{ percent: 100 }} height={{ percent: 100 }}>
            <SidebarGroup>
                <SidebarGroupContent>
                    <SidebarMenu>
                        <For each={filetree()}>
                            {(entry) => (
                                <SidebarMenuItem>
                                    <SidebarMenuButton bg={theme()?.sidebar ?? "#1e1e2e"} fg={theme()?.sidebarFg ?? "#cdd6f4"} onClick={() => app.expandEntry(entry.id)}>
                                        {" ".repeat(entry.depth)}{entry.kind === "dir" ? (entry.expanded ? "▾ " : "▸ ") : "  "}{entry.name}
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                            )}
                        </For>
                    </SidebarMenu>
                </SidebarGroupContent>
            </SidebarGroup>
        </scrollable>
    );
}

export function AppSidebar() {
    const theme = useTheme();
    return (
        <Sidebar>
            <SidebarHeader>
                <box bg={theme()?.sidebar ?? "#1e1e2e"} fg={theme()?.sidebarFg ?? "#cdd6f4"} height={{ point: 1 }}>Ares</box>
            </SidebarHeader>
            <SidebarContent overflow="hidden">
                <FileTree />
            </SidebarContent>
        </Sidebar>
    );
}
