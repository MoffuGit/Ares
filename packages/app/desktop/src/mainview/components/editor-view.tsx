import { useRef, useCallback, useEffect } from "react";
import { GpuTag, type GpuTagHandle } from "./gpu-tag";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorView as EditorViewData, Tab } from "@ares/shared";

interface EditorViewProps {
    tab: Tab;
    view: EditorViewData;
    active: boolean;
}

export function EditorView({ tab, view, active }: EditorViewProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuViewId: number) => {
        useAppStore.getState().setGpuViewId(tab.id, gpuViewId);

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
                if (view.entry != null) {
                    rpc.send("selectEntry", { viewId: gpuViewId, id: view.entry.id });
                }
            }
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [tab.id, view]);

    const handleResize = useCallback((viewId: number, rect: { x: number; y: number; width: number; height: number }) => {
        rpc.send("gpuTagRect", { id: viewId, rect });
    }, []);


    useEffect(() => {
        if (view.gpuViewId != null) {
            rpc.send("gpuTagVisibility", { id: view.gpuViewId, visible: active });
        }

    }, [active]);

    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative p-2">
                <GpuTag
                    ref={gpuRef}
                    id={`gpu-${tab.id}`}
                    style={{ width: "100%", height: "100%", backgroundColor: "transparent" }}
                    hidden={!active}
                    onReady={handleReady}
                    onResize={handleResize}
                />
            </div>
        </div>
    );
}
