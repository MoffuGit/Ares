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
                    {filetree && filetree.map((item) => (
                        <SidebarMenuItem key={item.id}>
                            <SidebarMenuButton onClick={() => app.selectEntry(item.id)} size="xs" style={{ paddingLeft: `${12 * (item.depth) + 8}px` }} >
                                <FileIcon item={item} />
                                <div>{item.name}</div>
                            </SidebarMenuButton>
                        </SidebarMenuItem>
                    ))}
                </SidebarMenu>
            </SidebarGroupContent>
        </SidebarGroup>
    )
}
// className="pl-[calc(2px*data-[])]"
