import { useAppStore } from "@/lib/app";
import { Tabs, TabsList } from "../ui/tabs";
import { TabTrigger } from "../tab-trigger";

export function TopBar() {
    const { setActiveTab, tabs, activeTabId } = useAppStore.getState();
    const tabsPosition = useAppStore((s) => s.settings?.tabs_position ?? "horizontal");
    const showTopTabs = tabsPosition === "horizontal";
    return (
        <div className='shrink-0 bg-sidebar cursor-default electrobun-webkit-app-region-drag pt-1.5 mx-2'>
            <div className="h-6 max-w-full w-fit flex items-center gap-1.5 overflow-hidden electrobun-webkit-app-region-no-drag pl-15">
                {showTopTabs && (
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
    )
}
