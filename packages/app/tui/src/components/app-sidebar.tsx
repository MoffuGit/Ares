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

    return (
        <SidebarGroup>
            <SidebarGroupContent>
                <SidebarMenu>
                    <For each={filetree()}>
                        {(entry) => (
                            <SidebarMenuItem>
                                <SidebarMenuButton onClick={() => app.selectEntry(entry.id)}>
                                    {" ".repeat(entry.depth)}{entry.kind === "dir" ? (entry.expanded ? "▾ " : "▸ ") : "  "}{entry.name}
                                </SidebarMenuButton>
                            </SidebarMenuItem>
                        )}
                    </For>
                </SidebarMenu>
            </SidebarGroupContent>
        </SidebarGroup>
    );
}

export function AppSidebar() {
    const theme = useTheme();
    return (
        <Sidebar>
            <SidebarHeader>
                <box bg="#00ff00" height={{ point: 1 }}>Ares</box>
            </SidebarHeader>
            <SidebarContent>
                <FileTree />
            </SidebarContent>
        </Sidebar>
    );
}
