import {
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar"
import { useApp, useFiletree } from '@ares/shared/react';
import { FileIcon } from "./file-icons";

export function FileTree() {
    const filetree = useFiletree();
    const app = useApp();

    return (
        <>
            <SidebarHeader>
                <SidebarMenu>
                    {
                        filetree && filetree.slice(0, 1).map((entry) => {
                            return (
                                <SidebarMenuItem key={entry.id}>
                                    <SidebarMenuButton onClick={() => app.expandEntry(entry.id)} size="xs" style={{ paddingLeft: `${16 * (entry.depth) + 8}px` }} >
                                        <FileIcon entry={entry} />
                                        <div className="text-clip text-nowrap">{entry.name}</div>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>

                            )
                        })
                    }
                </SidebarMenu>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupContent>
                        <SidebarMenu>
                            {filetree && filetree.slice(1).map((entry) => (
                                <SidebarMenuItem key={entry.id}>
                                    <SidebarMenuButton onClick={() => app.expandEntry(entry.id)} size="xs" style={{ paddingLeft: `${18 * (entry.depth) + 8}px` }} >
                                        <FileIcon entry={entry} />
                                        <div className="text-clip text-nowrap">{entry.name}</div>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                            ))}
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
        </>
    )
}
