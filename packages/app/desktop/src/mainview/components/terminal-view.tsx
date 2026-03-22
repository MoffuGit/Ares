import { GpuTag } from "./gpu-tag";
import type { TerminalView as TerminalViewData } from "@ares/shared";

interface TerminalViewProps {
    tabId: number;
    view: TerminalViewData;
}

export function TerminalView({ tabId, view }: TerminalViewProps) {
    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative">
                <GpuTag tabId={tabId} view={view} />
            </div>
        </div>
    );
}
