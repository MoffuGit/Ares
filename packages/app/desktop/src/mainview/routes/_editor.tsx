import { createFileRoute, Outlet } from '@tanstack/react-router'
import type { WorktreeEntry } from "@ares/shared"
import {
    SidebarProvider,
    Sidebar,
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarGroupLabel,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarRail,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { TooltipProvider } from '@/components/ui/tooltip';
import { useApp, useFiletree } from '@ares/shared/react';

function FileIcon({ entry }: { entry: WorktreeEntry }) {
    if (entry.kind === "dir") return <span>📁</span>;
    return <span>📄</span>;
}


export const Route = createFileRoute('/_editor')({
    component: () => (
        <TooltipProvider>
            <SidebarProvider>
                <div className='w-full h-screen overflow-hidden flex flex-col flex-1 content-stretch'>
                    <div className='w-full h-7 shrink-0  pl-18 bg-sidebar cursor-default electrobun-webkit-app-region-drag'>
                        <div className="w-auto h-full flex items-center gap-2 electrobun-webkit-app-region-no-drag">
                            <SidebarTrigger size="icon-xs" />
                        </div>
                    </div>
                    <div className='flex-1 flex flex-row overflow-hidden px-4 bg-sidebar'>
                        <AppSidebar />
                        <SidebarInset className='rounded-md bg-muted'>
                            <div className="flex flex-col gap-4 p-4">
                                <div className="grid auto-rows-min gap-4 md:grid-cols-3">
                                    <div className="aspect-video rounded-sm bg-muted" />
                                    <div className="aspect-video rounded-sm bg-muted/50" />
                                    <div className="aspect-video rounded-sm bg-muted/50" />
                                </div>
                                <div className="min-h-[100vh] flex-1 rounded-xl bg-muted/50 md:min-h-min" />
                            </div>
                        </SidebarInset>
                    </div>
                    <div className='bg-sidebar h-4 w-full' />
                </div>
            </SidebarProvider>
        </TooltipProvider>
    ),
})


function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    const filetree = useFiletree();
    const app = useApp();

    return (
        <Sidebar {...props}>
            <SidebarHeader>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup >
                    <SidebarGroupContent>
                        <SidebarMenu>
                            {filetree && filetree.map((item) => (
                                <SidebarMenuItem key={item.id}>
                                    <SidebarMenuButton onClick={() => app.selectEntry(item.id)} size="xs">
                                        <div >{item.name}</div>
                                    </SidebarMenuButton>
                                </SidebarMenuItem>
                            ))}
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
            <SidebarRail />
        </Sidebar>
    )
}
