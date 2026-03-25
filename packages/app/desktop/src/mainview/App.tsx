import { useEffect, useState } from 'react'
import { keymapHandler, useAppStore, onKeymapSequence } from '@/lib/app'
import {
    SidebarProvider,
    SidebarInset,
    SidebarTrigger,
} from "@/components/ui/sidebar"
import { Tabs, TabsList } from "@/components/ui/tabs"
import { TooltipProvider } from '@/components/ui/tooltip'
import { AppSidebar } from '@/components/app-sidebar'
import { TabContent } from '@/components/tab-content'
import type { Scope, ScopeActionMap } from '@ares/shared'
import { TabTrigger } from './components/tab-trigger'

function useScopedKeymaps<S extends Scope>(scope: S): Record<string, ScopeActionMap[S]> {
    const keymaps = useAppStore((s) => s.keymaps);
    const bindings = keymaps?.[scope] ?? [];
    const map: Record<string, ScopeActionMap[S]> = {};
    for (const b of bindings) {
        map[b.sequence] = b.action as ScopeActionMap[S];
    }
    return map;
}

function App() {
    const [open, setOpen] = useState(false);
    const globalKeymaps = useScopedKeymaps("global");
    const tabs = useAppStore((s) => s.tabs);
    const activeTabId = useAppStore((s) => s.activeTabId);
    const { newTab, closeTab, setActiveTab, nextTab, prevTab, setMode } = useAppStore.getState();

    useEffect(() => {
        const onKeyDown = (e: KeyboardEvent) => {
            const consumed = keymapHandler.handleKeyDown(e.key, {
                shift: e.shiftKey,
                alt: e.altKey,
                ctrl: e.ctrlKey,
                super: e.metaKey,
                hyper: false,
                meta: false,
                caps_lock: e.getModifierState('CapsLock'),
                num_lock: e.getModifierState('NumLock'),
            });

            if (consumed) {
                e.preventDefault();
                e.stopPropagation();
            }
        };
        document.addEventListener('keydown', onKeyDown);
        return () => document.removeEventListener('keydown', onKeyDown);
    }, []);

    useEffect(() => {
        return onKeymapSequence((sequence) => {
            const action = globalKeymaps[sequence];
            switch (action) {
                case "workspace:toggle_left_sidebar":
                    setOpen((prev) => !prev);
                    break;
                case "workspace:new_tab":
                    newTab({ kind: "editor", path: "" });
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
                        <div className="h-6 max-w-full w-fit flex items-center gap-1 overflow-hidden electrobun-webkit-app-region-no-drag pl-14">
                            <SidebarTrigger size="icon-xs" />
                            {tabs.length > 0 && (
                                <Tabs
                                    value={activeTabId != null ? String(activeTabId) : undefined}
                                    onValueChange={(val) => setActiveTab(Number(val))}
                                >
                                    <TabsList className="h-7 bg-sidebar gap-1">
                                        {tabs.map((tab) => (
                                            <TabTrigger
                                                key={tab.id}
                                                tab={tab}
                                            />
                                        ))}
                                    </TabsList>
                                </Tabs>
                            )}
                        </div>
                    </div>
                    <div className='flex-1 flex flex-row bg-sidebar'>
                        <AppSidebar />
                        <SidebarInset className='rounded-xl bg-muted shadow-inset isolate'>
                            {tabs.map((tab) => (
                                <div
                                    key={tab.id}
                                    className="w-full h-full absolute inset-0"
                                    data-active-tab={tab.id === activeTabId}
                                >
                                    <TabContent tab={tab} active={tab.id === activeTabId} />
                                </div>
                            ))}
                        </SidebarInset>
                    </div>
                </div>
            </SidebarProvider>
        </TooltipProvider>
    );
}

export default App
