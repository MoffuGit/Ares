import { createFileRoute, Outlet } from '@tanstack/react-router'
import {
    SidebarProvider,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { TooltipProvider } from '@/components/ui/tooltip';
import { AppSidebar } from '@/components/app-sidebar';
import { useState, useEffect } from 'react';
import { useAppStore, onKeymapSequence } from '@/lib/app';
import type { Scope, ScopeActionMap } from '@ares/shared';

function useScopedKeymaps<S extends Scope>(scope: S): Record<string, ScopeActionMap[S]> {
    const keymaps = useAppStore((s) => s.keymaps);
    const bindings = keymaps?.[scope] ?? [];
    const map: Record<string, ScopeActionMap[S]> = {};
    for (const b of bindings) {
        map[b.sequence] = b.action as ScopeActionMap[S];
    }
    return map;
}

export const Route = createFileRoute('/_editor')({
    component: EditorComponent,
})

function EditorComponent() {
    const [open, setOpen] = useState(false);
    const globalKeymaps = useScopedKeymaps("global");

    useEffect(() => {
        return onKeymapSequence((sequence) => {
            const action = globalKeymaps[sequence];
            if (action === "workspace:toggle_left_sidebar") {
                setOpen((prev) => !prev);
            }
        });
    }, [globalKeymaps]);
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
