import { useAppStore } from "@/lib/app";
import { Tabs, TabsList } from "../ui/tabs";
import { TabTrigger } from "../tab-trigger";
import { Button } from "../ui/button";

export function TopBar() {
    const { setActiveTab } = useAppStore.getState();
    const tabsPosition = useAppStore((s) => s.settings?.tabs_position ?? "horizontal");
    const activeTabId = useAppStore((s) => s.activeTabId);
    const tabs = useAppStore((s) => s.tabs);
    const project = useAppStore((s) => s.project);
    const showTopTabs = tabsPosition === "horizontal";
    return (
        <div className='shrink-0 bg-sidebar cursor-default electrobun-webkit-app-region-drag pt-1.5 flex items-center'>
            <div className="h-6 max-w-full w-fit flex items-center gap-1.5 overflow-hidden electrobun-webkit-app-region-no-drag pl-17">
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
            {project && (
                <Button
                    size="xs"
                    variant="ghost"
                    className="ml-auto mr-0 font-normal electrobun-webkit-app-region-no-drag px-1.5 text-xs text-muted-foreground/80 hover:bg-muted/60 hover:text-foreground/80"
                >
                    <span className="min-w-0 truncate">{project.name}</span>
                </Button>
            )}
        </div>
    )
}
