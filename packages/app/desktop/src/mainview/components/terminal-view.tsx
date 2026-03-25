import { useRef, useCallback } from "react";
import { GpuTag, type GpuTagHandle } from "./gpu-tag";
import { rpc, useAppStore } from "@/lib/app";
import type { TerminalSurface as TerminalSurfaceData } from "@ares/shared";

interface TerminalSurfaceProps {
    tabId: number;
    view: TerminalSurfaceData;
    active: boolean;
}

export function TerminalSurface({ tabId, view, active }: TerminalSurfaceProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuSurfaceId: number) => {
        useAppStore.getState().setGpuSurfaceId(tabId, gpuSurfaceId);

        const el = gpuRef.current?.element;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        try {
            await rpc.request.gpuTagReady({
                id: gpuSurfaceId,
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
