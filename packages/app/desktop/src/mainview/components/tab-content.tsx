import type { Tab } from "@ares/shared";
import { Surface } from "./surfaces";

interface TabContentProps {
    tab: Tab;
    active: boolean;
}

export function TabContent({ tab, active }: TabContentProps) {
    return (
        <div
            key={tab.id}
            className="w-full h-full absolute inset-0 p-2 flex"
        >
            <Surface surface={tab.surface} id={tab.id} active={active} />
        </div>
    );
}
