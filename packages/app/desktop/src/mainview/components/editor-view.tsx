import { WgpuTag } from "./wgpu-tag";
import type { EditorView as EditorViewData } from "@ares/shared";

interface EditorViewProps {
    tabId: number;
    view: EditorViewData;
}

export function EditorView({ tabId, view }: EditorViewProps) {
    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative">
                <WgpuTag tabId={tabId} view={view} />
            </div>
        </div>
    );
}
