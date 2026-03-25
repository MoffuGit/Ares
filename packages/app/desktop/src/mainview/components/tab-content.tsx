import type { Tab } from "@ares/shared";
import { EditorSurface } from "./editor";
import { TerminalSurface } from "./terminal-view";

interface TabContentProps {
    tab: Tab;
    active: boolean;
}

export function TabContent({ tab, active }: TabContentProps) {
    switch (tab.surface.kind) {
        case "editor":
            return <EditorSurface tab={tab} surface={tab.surface} active={active} />;
        case "terminal":
            return <TerminalSurface tabId={tab.id} view={tab.surface} active={active} />;
    }
}
