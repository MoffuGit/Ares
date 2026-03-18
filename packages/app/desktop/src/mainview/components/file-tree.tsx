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
// import {
//     SidebarContent,
//     SidebarHeader,
//     SidebarMenu,
//     SidebarMenuButton,
//     SidebarMenuItem,
// } from "@/components/ui/sidebar"
// import { useApp, useFiletree } from '@ares/shared/react';
// import { FileIcon } from "./file-icons";
// import { VirtualizedList } from "./virtualized-list";
// import { useCallback } from "react";
//
// export function FileTree() {
//     const filetree = useFiletree();
//     const app = useApp();
//
//     const entries = filetree?.slice(1) ?? [];
//
//     const renderItem = useCallback((index: number) => {
//         const entry = entries[index];
//         if (!entry) return null;
//         return (
//             <SidebarMenuButton key={entry.id} onClick={() => app.expandEntry(entry.id)} size="xs" style={{ paddingLeft: `${18 * (entry.depth) + 8}px` }} >
//                 <FileIcon entry={entry} />
//                 <div className="text-clip text-nowrap">{entry.name}</div>
//             </SidebarMenuButton>
//         );
//     }, [entries, app]);
//
//     return (
//         <>
//             <SidebarHeader>
//                 <SidebarMenu>
//                     {filetree && filetree.slice(0, 1).map((entry) => (
//                         <SidebarMenuItem key={entry.id}>
//                             <SidebarMenuButton onClick={() => app.expandEntry(entry.id)} size="xs" style={{ paddingLeft: `${16 * (entry.depth) + 8}px` }} >
//                                 <FileIcon entry={entry} />
//                                 <div className="text-clip text-nowrap">{entry.name}</div>
//                             </SidebarMenuButton>
//                         </SidebarMenuItem>
//                     ))}
//                 </SidebarMenu>
//             </SidebarHeader>
//             <SidebarContent className="group-data-[state=collapsed]:invisible">
//                 <VirtualizedList
//                     itemCount={entries.length}
//                     renderItem={renderItem}
//                 />
//             </SidebarContent>
//         </>
//     )
// }
