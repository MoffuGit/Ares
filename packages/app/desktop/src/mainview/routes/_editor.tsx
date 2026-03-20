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
import { Maximize2, Minus, X } from 'lucide-react';

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
    const { newTab, closeTab, setActiveTab, nextTab, prevTab, setMode } = useAppStore.getState();

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
                case "workspace:enter_insert":
                    setMode("insert")
                    break;
                case "workspace:enter_visual":
                    setMode("visual")
                    break;
                case "workspace:enter_normal":
                    setMode("normal")
                    break;
            }
        });
    }, [globalKeymaps, activeTabId]);
    return (
        <TooltipProvider>
            <SidebarProvider open={open} onOpenChange={setOpen}>
                <div className='w-full h-full flex flex-col flex-1 content-stretch rounded-3xl'>
                    <div className='shrink-0 bg-sidebar cursor-default electrobun-webkit-app-region-drag mb-2 pt-2 mx-2'>
                        <div className="h-6 w-full flex items-center gap-1 overflow-hidden electrobun-webkit-app-region-no-drag">
                            <div className="flex gap-2 group">
                                <button
                                    className="w-3 h-3 rounded-full bg-red-500 hover:bg-red-600 flex items-center justify-center text-black/0 hover:text-black/50 transition-all"
                                >
                                    <X size={8} />
                                </button>
                                <button
                                    className="w-3 h-3 rounded-full bg-yellow-500 hover:bg-yellow-600 flex items-center justify-center text-black/0 hover:text-black/50 transition-all"
                                >
                                    <Minus size={8} />
                                </button>
                                <button
                                    className="w-3 h-3 rounded-full bg-green-500 hover:bg-green-600 flex items-center justify-center text-black/0 hover:text-black/50 transition-all"
                                >
                                    <Maximize2 size={8} />
                                </button>
                            </div>
                            <SidebarTrigger size="icon-xs" />
                            {tabs.length > 0 && (
                                <Tabs
                                    value={activeTabId ?? undefined}
                                    onValueChange={(val) => setActiveTab(val)}
                                >
                                    <TabsList className="h-7 bg-sidebar gap-1">
                                        {tabs.map((tab) => (
                                            <TabsTrigger
                                                key={tab.id}
                                                value={tab.id}
                                            >
                                                {tab.name}
                                            </TabsTrigger>
                                        ))}
                                    </TabsList>
                                </Tabs>
                            )}
                        </div>
                    </div>
                    <div className='flex-1 flex flex-row bg-sidebar'>
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
