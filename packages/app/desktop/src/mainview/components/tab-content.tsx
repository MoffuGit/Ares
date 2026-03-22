import type { Tab } from "@ares/shared";
import { EditorView } from "./editor-view";
import { TerminalView } from "./terminal-view";

interface TabContentProps {
    tab: Tab;
}

export function TabContent({ tab }: TabContentProps) {
    switch (tab.view.kind) {
        case "editor":
            return <EditorView tabId={tab.id} view={tab.view} />;
        case "terminal":
            return <TerminalView tabId={tab.id} view={tab.view} />;
    }
}
