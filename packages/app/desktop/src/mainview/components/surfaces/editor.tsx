import { useRef, useCallback, useEffect } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag, GpuTagHandle } from "../gpu-tag";

interface EditorSurfaceProps {
    id: number;
    surface: EditorSurfaceData;
    active: boolean;
}

export function EditorSurface({ id, surface, active }: EditorSurfaceProps) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuSurfaceId: number) => {
        useAppStore.getState().setGpuSurfaceId(id, gpuSurfaceId);

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
    }, [id, surface]);

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
        <div className="w-full grow relative">
            <div className="absolute top-0 w-full h-full overflow-auto">
                <div style={{ "height": surface.bufferState ? surface.bufferState.rowCount * 16 : 0 }} />
            </div>
            <GpuTag
                ref={gpuRef}
                id={`gpu-${id}`}
                style={{ width: "100%", height: "100%", backgroundColor: "transparent" }}
                passthrough={true}
                hidden={!active}
                onReady={handleReady}
                onResize={handleResize}
            />
        </div>
    );
}
