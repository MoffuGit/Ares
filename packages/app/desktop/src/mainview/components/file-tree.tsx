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
import { WorktreeEntry } from "@ares/shared";

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
                                <FileTreeItem entry={entry} />
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
                                        <FileTreeItem entry={entry} />
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

function FileTreeItem({ entry }: { entry: WorktreeEntry }) {
    const clickEntry = useAppStore((state) => state.clickEntry);
    return (
        <SidebarMenuItem key={entry.id}>
            <SidebarMenuButton
                onClick={() => clickEntry(entry)}
                size="xs" style={{ paddingLeft: `${18 * (entry.depth) + 8}px` }} >
                <FileIcon entry={entry} />
                <div className="text-clip text-nowrap">{entry.name}</div>
            </SidebarMenuButton>
        </SidebarMenuItem>
    )
}
