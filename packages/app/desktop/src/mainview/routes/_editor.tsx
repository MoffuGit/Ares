import { createFileRoute, Outlet } from '@tanstack/react-router'
import {
    SidebarProvider,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { TooltipProvider } from '@/components/ui/tooltip';
import { AppSidebar } from '@/components/app-sidebar';
import { useEffect, useState } from 'react';
import { useApp, useScopedKeymaps } from '@ares/shared/react';

export const Route = createFileRoute('/_editor')({
    component: EditorComponent,
})

function EditorComponent() {
    const [open, setOpen] = useState(false);
    const app = useApp()
    const keymaps = useScopedKeymaps("global");

    useEffect(() => {
        const handler = (sequence: string) => {
            const action = keymaps[sequence];
            if (action === "workspace:toggle_left_sidebar") {
                setOpen((prev) => !prev);
            }
        };
        app.events.on("keymapSequence", handler);
        return () => app.events.off("keymapSequence", handler);
    }, [app, keymaps]);
    return (
        <TooltipProvider>
            <SidebarProvider open={open} onOpenChange={setOpen}>
                <div className='w-full h-screen flex flex-col flex-1 content-stretch'>
                    <div className='w-full h-7 shrink-0  pl-18 bg-sidebar cursor-default electrobun-webkit-app-region-drag'>
                        <div className="w-auto h-full flex items-center gap-2 electrobun-webkit-app-region-no-drag">
                            <SidebarTrigger size="icon-xs" />
                        </div>
                    </div>
                    <div className='flex-1 flex flex-row px-2 pb-2 bg-sidebar'>
                        <AppSidebar />
                        <SidebarInset className='rounded-xl bg-muted shadow-inset'>
                            <Outlet />
                        </SidebarInset>
                    </div>
                </div>
            </SidebarProvider>
        </TooltipProvider>
    );
}
