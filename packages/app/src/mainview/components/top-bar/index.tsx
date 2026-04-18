import { useAppStore } from "@/lib/app";
import { Tabs, TabsList } from "../ui/tabs";
import { TabTrigger } from "../tab-trigger";
import { Button } from "../ui/button";
import { Terminal } from "lucide-react";

function TopBarInfo() {
    const activeTabId = useAppStore((s) => s.activeTabId);
    const tabs = useAppStore((s) => s.tabs);
    const activeTab = tabs.find((t) => t.id === activeTabId);

    if (!activeTab) return null;

    const surface = activeTab.surface;

    if (surface.kind === "editor" && surface.entry) {
        const parts = surface.entry.path.split("/").slice(1).join("/");
        return (
            <div className="font-normal dark:text-foreground/70 text-foreground text-xs leading-none">
                {parts}
            </div>
        );
    }

    if (surface.kind === "terminal") {
        return (
            <div className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Terminal className="size-3" />
                <span>Terminal</span>
            </div>
        );
    }

    if (surface.kind === "editor") {
        return (
            <span className="text-xs text-muted-foreground italic">No file selected</span>
        );
    }

    return null;
}

function useTopBarInfo() {
    const activeTabId = useAppStore((s) => s.activeTabId);
    const tabs = useAppStore((s) => s.tabs);
    const activeTab = tabs.find((t) => t.id === activeTabId);
    if (!activeTab) return null;
    return activeTab.surface;
}

export function TopBar() {
    const { setActiveTab } = useAppStore.getState();
    const tabsPosition = useAppStore((s) => s.settings?.tabs_position ?? "horizontal");
    const activeTabId = useAppStore((s) => s.activeTabId);
    const tabs = useAppStore((s) => s.tabs);
    const project = useAppStore((s) => s.project);
    const showTopTabs = tabsPosition === "horizontal";
    const surface = useTopBarInfo();
    const hasInfo = surface !== null && (surface.kind === "terminal" || surface.kind === "editor");

    return (
        <div className='shrink-0 bg-sidebar cursor-default electrobun-webkit-app-region-drag pt-1.5 grid grid-cols-[minmax(0,1fr)_minmax(33%,auto)_minmax(0,1fr)] items-center'>
            <div className="min-w-0">
                <div className="h-6 ml-17 max-w-full w-fit flex items-center gap-1.5 overflow-hidden electrobun-webkit-app-region-no-drag">
                    {showTopTabs && (
                        <Tabs
                            value={activeTabId}
                            onValueChange={(val) => setActiveTab(val)}
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
            <div className="min-w-0">
                {hasInfo && (
                    <div className="flex min-w-0 w-full items-center justify-center px-2 bg-muted h-6 rounded-md shadow-inset dark:border border-border/50">
                        <div className="electrobun-webkit-app-region-no-drag">
                            <TopBarInfo />
                        </div>
                    </div>
                )}
            </div>
            <div className="flex min-w-0 justify-end">
                {project && (
                    <Button
                        size="xs"
                        variant="ghost"
                        className="font-normal electrobun-webkit-app-region-no-drag px-1.5 text-xs text-muted-foreground/80 hover:bg-muted/60 hover:text-foreground/80"
                    >
                        <span className="min-w-0 truncate">{project.name}</span>
                    </Button>
                )}
            </div>
        </div>
    )
}
