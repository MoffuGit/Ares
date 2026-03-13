import { createFileRoute } from '@tanstack/react-router'
import {
    SidebarProvider,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { TooltipProvider } from '@/components/ui/tooltip';
import { AppSidebar } from '@/components/app-sidebar';

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
                        <SidebarInset className='rounded-xl bg-muted'>
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
