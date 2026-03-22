import { WgpuTag } from "./wgpu-tag";
import type { TerminalView as TerminalViewData } from "@ares/shared";

interface TerminalViewProps {
    tabId: number;
    view: TerminalViewData;
}

export function TerminalView({ tabId, view }: TerminalViewProps) {
    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative">
                <WgpuTag tabId={tabId} view={view} />
            </div>
        </div>
    );
}
