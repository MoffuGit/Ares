import { useAppStore } from "@/lib/app";
import type { Tab } from "@ares/shared";
import {
    SidebarContent,
    SidebarGroup,
    SidebarGroupContent,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from "@/components/ui/sidebar";
import { Button } from "./ui/button";
import { FileIcon } from "./file-icons";
import { ChevronDown, X } from "lucide-react";

export function SidebarTabs() {
    const tabs = useAppStore((state) => state.tabs);
    const project = useAppStore((state) => state.project);

    return (
        <>
            <SidebarHeader>
                <SidebarMenu className="pl-1">
                    <SidebarMenuItem>
                        <SidebarMenuButton size="sm">
                            <span className="truncate font-medium">{project?.name}</span>
                            <ChevronDown className="opacity-50 ml-auto mr-0 invisible group-hover/menu-item:visible" />
                        </SidebarMenuButton>
                    </SidebarMenuItem>
                </SidebarMenu>
            </SidebarHeader>
            <SidebarContent>
                <SidebarGroup className="p-1">
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

function SidebarTabsItem({ tab }: { tab: Tab }) {
    const activeTabId = useAppStore((state) => state.activeTabId);
    const setActiveTab = useAppStore((state) => state.setActiveTab);
    const closeTab = useAppStore((state) => state.closeTab);

    return (
        <SidebarMenuItem>
            <SidebarMenuButton
                isActive={tab.id === activeTabId}
                className="pr-7 dark:text-sidebar-accent-foreground/50"
                size="xs"
                onClick={() => setActiveTab(tab.id)}
            >
                {tab.surface.kind === "editor" && tab.surface.entry ? (
                    <FileIcon entry={tab.surface.entry} />
                ) : null}
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
