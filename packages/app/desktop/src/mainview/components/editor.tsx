import { useRef, useCallback, useEffect } from "react";
import { GpuTag, type GpuTagHandle } from "./gpu-tag";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData, Tab } from "@ares/shared";

interface EditorSurfaceProps {
    tab: Tab;
    surface: EditorSurfaceData;
    active: boolean;
}

export function EditorSurface({ tab, surface, active }: EditorSurfaceProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuSurfaceId: number) => {
        useAppStore.getState().setGpuSurfaceId(tab.id, gpuSurfaceId);

        const el = gpuRef.current?.element;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        try {
            const res = await rpc.request.gpuTagReady({
                id: gpuSurfaceId,
                rect: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
                surface,
            });
            if (res.success) {
                if (surface.entry != null) {
                    rpc.send("selectSurfaceEntry", { surfaceId: gpuSurfaceId, id: surface.entry.id });
                }
            }
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [tab.id, surface]);

    const handleResize = useCallback((surfaceId: number, rect: { x: number; y: number; width: number; height: number }) => {
        rpc.send("gpuTagRect", { id: surfaceId, rect });
    }, []);


    useEffect(() => {
        gpuRef.current?.toggleHidden(!active);

        if (surface.gpuSurfaceId != null) {
            rpc.send("gpuTagVisibility", { id: surface.gpuSurfaceId, visible: active });
        }
    }, [active, surface.gpuSurfaceId]);

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
