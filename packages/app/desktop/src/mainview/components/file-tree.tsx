import {
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar"
import { FileIcon } from "./file-icons";
import { VirtualizedList } from "./virtual-list";
import { useAppStore } from "@/lib/app";

export function FileTree() {
    const filetree = useAppStore((state) => state.filetree);

    if (!filetree) return null;

    return (
        <>
            <SidebarHeader>
                <SidebarMenu>
                    {
                        filetree.slice(0, 1).map((entry) => {
                            return (
                                <SidebarMenuItem key={entry.id}>
                                    <SidebarMenuButton size="xs" style={{ paddingLeft: `${16 * (entry.depth) + 8}px` }} >
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
                            {
                                filetree.length > 0 && <VirtualizedList itemCount={filetree.length - 1} itemHeight={24} renderItem={(index) => {
                                    const entry = filetree[index + 1];
                                    if (!entry) return null;

                                    return (
                                        <SidebarMenuItem key={entry.id}>
                                            <SidebarMenuButton size="xs" style={{ paddingLeft: `${18 * (entry.depth) + 8}px` }} >
                                                <FileIcon entry={entry} />
                                                <div className="text-clip text-nowrap">{entry.name}</div>
                                            </SidebarMenuButton>
                                        </SidebarMenuItem>
                                    )
                                }} />
                            }
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
        </>
    )
}
// onClick={() => app.expandEntry(entry.id)}
// onClick={() => {
//                                                 if (entry.kind == "dir") {
//                                                     app.expandEntry(entry.id)
//                                                 } else {
//                                                     const buffer = app.readBuffer(entry.id);
//                                                     if (buffer) {
//                                                         console.log(buffer);
//                                                     }
//                                                 }
//                                             }}
