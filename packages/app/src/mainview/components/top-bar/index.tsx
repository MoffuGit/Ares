import React from "react";
import { useAppStore } from "@/lib/app";
import { Tabs, TabsList } from "../ui/tabs";
import { TabTrigger } from "../tab-trigger";
import { Button } from "../ui/button";
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator } from "../ui/breadcrumb";
import { FileIcon } from "../file-icons";
import { Terminal } from "lucide-react";

function TopBarInfo() {
    const activeTabId = useAppStore((s) => s.activeTabId);
    const tabs = useAppStore((s) => s.tabs);
    const activeTab = tabs.find((t) => t.id === activeTabId);

    if (!activeTab) return null;

    const surface = activeTab.surface;

    if (surface.kind === "editor" && surface.entry) {
        const parts = surface.entry.path.split("/").slice(1);
        return (
            <Breadcrumb>
                <BreadcrumbList>
                    {parts.map((part, i) => (
                        <React.Fragment key={i}>
                            {i > 0 && <BreadcrumbSeparator />}
                            <BreadcrumbItem>
                                {i === parts.length - 1 && surface.entry && (
                                    <BreadcrumbPage>
                                        <FileIcon entry={surface.entry} />
                                    </BreadcrumbPage>
                                )}
                                <BreadcrumbPage>{part}</BreadcrumbPage>
                            </BreadcrumbItem>
                        </React.Fragment>
                    ))}
                </BreadcrumbList>
            </Breadcrumb>
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
            <div className="flex items-center px-2 electrobun-webkit-app-region-no-drag">
                <TopBarInfo />
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
