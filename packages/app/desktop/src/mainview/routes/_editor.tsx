import { createFileRoute, Outlet } from '@tanstack/react-router'
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
                            <Outlet />
                        </SidebarInset>
                    </div>
                    <div className='bg-sidebar h-4 w-full' />
                </div>
            </SidebarProvider>
        </TooltipProvider>
    ),
})
