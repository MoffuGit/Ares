import { useRef, useCallback } from "react";
import { GpuTag, type GpuTagHandle } from "./gpu-tag";
import { rpc, useAppStore } from "@/lib/app";
import type { TerminalView as TerminalViewData } from "@ares/shared";

interface TerminalViewProps {
    tabId: number;
    view: TerminalViewData;
    active: boolean;
}

export function TerminalView({ tabId, view, active }: TerminalViewProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuViewId: number) => {
        useAppStore.getState().setGpuViewId(tabId, gpuViewId);

        const el = gpuRef.current?.element;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        try {
            await rpc.request.gpuTagReady({
                id: gpuViewId,
                rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
                view,
            });
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [tabId, view]);

    return (
        <div className="min-w-fit h-full flex flex-col">
            <div className="w-full grow relative">
                <GpuTag
                    ref={gpuRef}
                    id={`gpu-${tabId}`}
                    style={{ width: "100%", height: "100%", backgroundColor: "transparent" }}
                    hidden={!active}
                    onReady={handleReady}
                />
            </div>
        </div>
    );
}
