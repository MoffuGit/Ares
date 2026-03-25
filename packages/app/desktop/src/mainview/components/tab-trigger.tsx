import type { Tab } from "@ares/shared";
import { TabsTrigger } from "./ui/tabs";
import { X } from "lucide-react";
import { useAppStore } from "@/lib/app";
import { FileIcon } from "./file-icons";

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
                tab.view.kind == "editor" && tab.view.entry && (
                    <FileIcon entry={tab.view.entry} />
                )
            }
            {tab.name}
            <X
                onClick={() => { closeTab(tab.id) }}
                className="ml-auto mr-0 group-hover/tab-trigger:opacity-100 opacity-0 pointer-events-auto"
            />
        </TabsTrigger>
    );
}
