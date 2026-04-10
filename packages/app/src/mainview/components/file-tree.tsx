import {
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar"
import { FileIcon } from "./file-icons";
import { VirtualizedList } from "./virtual-list";
import { useAppStore } from "@/lib/app";
import type { WorktreeEntry } from "@ares/shared";

export function FileTree() {
    const filetree = useAppStore((state) => state.filetree);

    if (!filetree) return null;

    return (
        <SidebarContent>
            <SidebarGroup className="pr-1">
                <SidebarGroupContent>
                    <SidebarMenu>
                        {
                            <VirtualizedList itemCount={filetree.length} itemHeight={24} renderItem={(index) => {
                                const entry = filetree[index];
                                if (!entry) return null;

                                return (
                                    <FileTreeItem entry={entry} key={entry.id} />
                                )
                            }} />
                        }
                    </SidebarMenu>
                </SidebarGroupContent>
            </SidebarGroup>
        </SidebarContent>
    )
}

function FileTreeItem({ entry }: { entry: WorktreeEntry }) {
    const expandEntry = useAppStore((state) => state.expandEntry);
    const selectSurfaceEntry = useAppStore((state) => state.selectSurfaceEntry);
    return (
        <SidebarMenuItem key={entry.id}>
            <SidebarMenuButton
                className="dark:text-sidebar-accent-foreground/50"
                onClick={() => {
                    if (entry.kind == "dir") {
                        expandEntry(entry)
                    } else {
                        selectSurfaceEntry(entry)
                    }
                }}
                size="xs" style={{ paddingLeft: `${18 * (entry.depth) + 8}px` }} >
                <FileIcon
                    entry={entry}
                />
                <div className="text-clip text-nowrap">{entry.name}</div>
            </SidebarMenuButton>
        </SidebarMenuItem>
    )
}
