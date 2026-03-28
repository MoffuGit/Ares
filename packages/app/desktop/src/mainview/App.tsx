import { useEffect } from 'react'
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
import { BottomBar } from './components/bottom-bar'

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
    const globalKeymaps = useScopedKeymaps("global");
    const tabs = useAppStore((s) => s.tabs);
    const activeTabId = useAppStore((s) => s.activeTabId);
    const sidebarOpen = useAppStore((s) => s.sidebarOpen);
    const { newTab, closeTab, setActiveTab, nextTab, prevTab, setMode, setSidebarOpen, toggleSidebar } = useAppStore.getState();

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
                    toggleSidebar();
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
            <SidebarProvider open={sidebarOpen} onOpenChange={setSidebarOpen}>
                <div className='w-full h-full flex flex-col flex-1 content-stretch gap-1.5'>
                    <div className='shrink-0 bg-sidebar cursor-default electrobun-webkit-app-region-drag pt-1.5 mx-2'>
                        <div className="h-6 max-w-full w-fit flex items-center gap-1.5 overflow-hidden electrobun-webkit-app-region-no-drag pl-15">
                            {tabs.length > 0 && (
                                <Tabs
                                    value={activeTabId != null ? String(activeTabId) : undefined}
                                    onValueChange={(val) => setActiveTab(Number(val))}
                                >
                                    <TabsList className="h-6 bg-sidebar gap-1">
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
                        <SidebarInset className='rounded-lg bg-muted shadow-inset flex flex-col border border-border/50'>
                            <div className='isolate relative grow w-full'>
                                {tabs.map((tab) => (
                                    <TabContent key={tab.id} tab={tab} active={tab.id === activeTabId} />
                                ))}
                            </div>
                        </SidebarInset>
                    </div>
                    <BottomBar />
                </div>
            </SidebarProvider>
        </TooltipProvider>
    );
}

export default App
