import type { Tab } from "@ares/shared";
import { EditorView } from "./editor-view";
import { TerminalView } from "./terminal-view";

interface TabContentProps {
    tab: Tab;
    active: boolean;
}

export function TabContent({ tab, active }: TabContentProps) {
    switch (tab.view.kind) {
        case "editor":
            return <EditorView tab={tab} view={tab.view} active={active} />;
        case "terminal":
            return <TerminalView tabId={tab.id} view={tab.view} active={active} />;
    }
}
