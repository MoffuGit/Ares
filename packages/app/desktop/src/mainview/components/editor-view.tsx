import { useRef, useCallback } from "react";
import { GpuTag, type GpuTagHandle } from "./gpu-tag";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorView as EditorViewData } from "@ares/shared";

interface EditorViewProps {
    tabId: number;
    view: EditorViewData;
}

export function EditorView({ tabId, view }: EditorViewProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuViewId: number) => {
        useAppStore.getState().setGpuViewId(tabId, gpuViewId);

        const el = gpuRef.current?.element;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        try {
            const res = await rpc.request.gpuTagReady({
                id: gpuViewId,
                rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
                view,
            });
            if (res.success) {
                const tab = useAppStore.getState().tabs.find((t) => t.id === tabId);
                if (tab?.entryId != null) {
                    rpc.send("selectEntry", { viewId: gpuViewId, id: tab.entryId });
                }
            }
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [tabId, view]);

    const handleResize = useCallback((viewId: number, rect: { x: number; y: number; width: number; height: number }) => {
        rpc.send("gpuTagRect", { id: viewId, rect });
    }, []);

    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative p-2">
                <GpuTag
                    ref={gpuRef}
                    id={`gpu-${tabId}`}
                    style={{ width: "100%", height: "100%", backgroundColor: "transparent" }}
                    onReady={handleReady}
                    onResize={handleResize}
                />
            </div>
        </div>
    );
}
