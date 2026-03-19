import { createFileRoute, Outlet } from '@tanstack/react-router'
import {
    SidebarProvider,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { TooltipProvider } from '@/components/ui/tooltip';
import { AppSidebar } from '@/components/app-sidebar';
import { useState, useEffect } from 'react';
import { useAppStore, onKeymapSequence } from '@/lib/app';
import type { Scope, ScopeActionMap } from '@ares/shared';
import { X } from 'lucide-react';

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
    const tabs = useAppStore((s) => s.tabs);
    const activeTabId = useAppStore((s) => s.activeTabId);
    const { newTab, closeTab, setActiveTab, nextTab, prevTab } = useAppStore.getState();

    useEffect(() => {
        return onKeymapSequence((sequence) => {
            const action = globalKeymaps[sequence];
            switch (action) {
                case "workspace:toggle_left_sidebar":
                    setOpen((prev) => !prev);
                    break;
                case "workspace:new_tab":
                    newTab();
                    break;
                case "workspace:next_tab":
                    nextTab();
                    break;
                case "workspace:prev_tab":
                    prevTab();
                    break;
                case "workspace:close_active_tab":
                    if (activeTabId != null) closeTab(activeTabId);
                    break;
            }
        });
    }, [globalKeymaps, activeTabId]);
    return (
        <TooltipProvider>
            <SidebarProvider open={open} onOpenChange={setOpen}>
                <div className='w-full h-screen flex flex-col flex-1 content-stretch'>
                    <div className='w-full h-7 shrink-0 pl-18 bg-sidebar cursor-default electrobun-webkit-app-region-drag'>
                        <div className="w-auto h-full flex items-center gap-2 electrobun-webkit-app-region-no-drag">
                            <SidebarTrigger size="icon-xs" />
                            {tabs.length > 0 && (
                                <Tabs
                                    value={activeTabId ?? undefined}
                                    onValueChange={(val) => setActiveTab(val)}
                                >
                                    <TabsList variant="line" className="h-7 gap-0">
                                        {tabs.map((tab) => (
                                            <TabsTrigger
                                                key={tab.id}
                                                value={tab.id}
                                                className="h-6 px-2 text-xs gap-1"
                                            >
                                                {tab.name}
                                                <X
                                                    className="size-3 opacity-50 hover:opacity-100"
                                                    onClick={(e) => {
                                                        e.stopPropagation();
                                                        closeTab(tab.id);
                                                    }}
                                                />
                                            </TabsTrigger>
                                        ))}
                                    </TabsList>
                                </Tabs>
                            )}
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
