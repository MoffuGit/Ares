import React, { useRef, useCallback, useEffect } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag, GpuTagHandle } from "../gpu-tag";
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator } from "../ui/breadcrumb";

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
        <div className="w-full flex flex-col grow data-[surface-active=true]:z-10 -z-10 data-[surface-active=true]:opacity-100 opacity-0" data-surface-active={active}>
            <div className="w-full h-7 flex items-center justify-start px-2">
                {surface.entry && (
                    <Breadcrumb>
                        <BreadcrumbList>
                            {surface.entry.path.split("/").map((part, i) => (
                                <React.Fragment key={i}>
                                    {i > 0 && <BreadcrumbSeparator />}
                                    <BreadcrumbItem>
                                        <BreadcrumbPage>{part}</BreadcrumbPage>
                                    </BreadcrumbItem>
                                </React.Fragment>
                            ))}
                        </BreadcrumbList>
                    </Breadcrumb>
                )}
            </div>
            <div className="w-full grow relative p-1.5">
                <div
                    className="absolute top-0 inset-0 w-full h-full overflow-auto data-[active-tab=true]:flex hidden"
                    data-active-tab={active}
                    data-slot="editor-content"
                >
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
        </div>
    );
}
