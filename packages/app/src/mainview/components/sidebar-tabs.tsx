import { useAppStore } from "@/lib/app";
import type { Tab } from "@ares/shared";
import {
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar";
import { Button } from "./ui/button";
import { FileIcon } from "./file-icons";
import { Plus, Terminal, X } from "lucide-react";

export function SidebarTabs() {
    const tabs = useAppStore((state) => state.tabs);

    return (
        <>
            <SidebarContent>
                <SidebarGroup>
                    <SidebarGroupContent>
                        <SidebarMenu>
                            {tabs.map((tab) => (
                                <SidebarTabsItem key={tab.id} tab={tab} />
                            ))}
                        </SidebarMenu>
                    </SidebarGroupContent>
                </SidebarGroup>
            </SidebarContent>
        </>
    );
}

function SidebarTabsIcon({ tab }: { tab: Tab }) {
    switch (tab.surface.kind) {
        case "editor":
            return tab.surface.entry ? (
                <FileIcon entry={tab.surface.entry} />
            ) : (
                <div className="size-3.5 flex items-center align-middle [&_svg:not([class*='size-'])]:size-3.5 dark:opacity-50">
                    <Plus />
                </div>
            )
        case "terminal":
            return (
                <div className="size-3.5 flex items-center align-middle [&_svg:not([class*='size-'])]:size-3.5 dark:opacity-50" >
                    <Terminal />
                </div>
            )
    }
}

function SidebarTabsItem({ tab }: { tab: Tab }) {
    const activeTabId = useAppStore((state) => state.activeTabId);
    const setActiveTab = useAppStore((state) => state.setActiveTab);
    const closeTab = useAppStore((state) => state.closeTab);

    return (
        <SidebarMenuItem>
            <SidebarMenuButton
                isActive={tab.id === activeTabId}
                className="dark:text-sidebar-accent-foreground/50"
                size="xs"
                onClick={() => setActiveTab(tab.id)}
            >
                <SidebarTabsIcon tab={tab} />
                <span className="truncate leading-none">{tab.name}</span>
            </SidebarMenuButton>
            <Button
                render={({ children, className }) => {
                    return (
                        <div
                            className={className}
                            onClick={(event) => {
                                event.stopPropagation();
                                closeTab(tab.id);
                            }}
                        >
                            {children}
                        </div>
                    );
                }}
                size="icon-xs"
                variant="ghost"
                className="!pointer-events-auto absolute right-0.5 top-1/2 size-5 -translate-y-1/2 bg-transparent opacity-0 transition-none hover:bg-sidebar-accent hover:text-sidebar-accent-foreground group-hover/menu-item:opacity-100"

            >
                <X />
            </Button>
        </SidebarMenuItem>
    );
}
