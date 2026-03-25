import type { Tab } from "@ares/shared";
import { TabsTrigger } from "./ui/tabs";
import { X } from "lucide-react";
import { useAppStore } from "@/lib/app";
import { FileIcon } from "./file-icons";
import { Button } from "./ui/button";

interface TabContentProps {
    tab: Tab;
}

export function TabTrigger({ tab }: TabContentProps) {
    const { closeTab } = useAppStore.getState();
    return (
        <TabsTrigger
            value={String(tab.id)}
        >
            {
                tab.surface.kind == "editor" && tab.surface.entry && (
                    <FileIcon entry={tab.surface.entry} />
                )
            }
            <span className="truncate">{tab.name}</span>
            <Button
                render={({ children, className }) => {
                    return <div className={className}>{children}</div>
                }}
                size="icon-xs"
                className="!pointer-events-auto absolute right-0.5 size-5 top-1/2 transition-none -translate-y-1/2 group-hover/tab-trigger:opacity-100 opacity-0 bg-muted hover:bg-background hover:text-foreground"
                onClick={(e) => { e.stopPropagation(); closeTab(tab.id); }}
            >
                <X />
            </Button>
        </TabsTrigger>
    );
}
