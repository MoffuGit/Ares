import {
    SidebarGroup,
    SidebarGroupContent,
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
        <SidebarGroup>
            <SidebarGroupContent>
                <SidebarMenu>
                    {filetree && filetree.map((entry) => (
                        <SidebarMenuItem key={entry.id}>
                            <SidebarMenuButton onClick={() => app.expandEntry(entry.id)} size="xs" style={{ paddingLeft: `${16 * (entry.depth) + 8}px` }} >
                                <FileIcon entry={entry} />
                                <div className="text-clip text-nowrap">{entry.name}</div>
                            </SidebarMenuButton>
                        </SidebarMenuItem>
                    ))}
                </SidebarMenu>
            </SidebarGroupContent>
        </SidebarGroup>
    )
}
// className="pl-[calc(2px*data-[])]"
