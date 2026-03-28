import React, { useRef, useCallback, useEffect } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag, GpuTagHandle } from "../gpu-tag";
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator, BreadcrumbEllipsis } from "../ui/breadcrumb";
import useResizeObserver from '@react-hook/resize-observer'

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

    useEffect(() => {
        gpuRef.current?.toggleHidden(!active);

        if (surface.gpuSurfaceId != null) {
            rpc.send("gpuTagVisibility", { id: surface.gpuSurfaceId, visible: active });
        }
    }, [active, surface.gpuSurfaceId]);

    const handleScroll = useCallback((e: React.UIEvent<HTMLDivElement>) => {
        if (!surface.gpuSurfaceId || !surface.bufferState) return;
        const cellHeight = surface.bufferState.cellHeight;
        if (cellHeight <= 0) return;
        const scrollTop = e.currentTarget.scrollTop;
        const row = Math.floor(scrollTop / cellHeight);
        rpc.send("surfaceScrollTo", { surfaceId: surface.gpuSurfaceId, row });
    }, [surface.gpuSurfaceId, surface.bufferState]);

    const divRef = useRef(null);

    useResizeObserver(divRef, (entry) => {
        if (!surface.gpuSurfaceId) return;
        const content = entry.contentRect;
        rpc.send("gpuTagRect", { id: surface.gpuSurfaceId, rect: { x: content.x, y: content.y, width: content.width, height: content.height } });
    })

    return (
        <div className="w-full flex flex-col grow data-[surface-active=true]:z-10 -z-10 data-[surface-active=true]:visible invisible" data-surface-active={active}>
            <div className="w-full h-8 flex items-center justify-start px-2">
                {surface.entry && (() => {
                    const parts = surface.entry.path.split("/").slice(1);
                    const collapsed = parts.length > 4;
                    const visible = collapsed
                        ? [parts[0], ...parts.slice(-3)]
                        : parts;
                    return (
                        <Breadcrumb>
                            <BreadcrumbList>
                                {visible.map((part, i) => (
                                    <React.Fragment key={collapsed && i > 0 ? parts.length - 4 + i : i}>
                                        {i > 0 && <BreadcrumbSeparator />}
                                        {collapsed && i === 1 && (
                                            <>
                                                <BreadcrumbItem>
                                                    <BreadcrumbEllipsis />
                                                </BreadcrumbItem>
                                                <BreadcrumbSeparator />
                                            </>
                                        )}
                                        <BreadcrumbItem>
                                            <BreadcrumbPage>{part}</BreadcrumbPage>
                                        </BreadcrumbItem>
                                    </React.Fragment>
                                ))}
                            </BreadcrumbList>
                        </Breadcrumb>
                    );
                })()}
            </div>
            <div className="w-full grow relative flex px-4">
                <div
                    className="absolute top-0 inset-0 w-full h-full overflow-auto data-[active-tab=true]:flex hidden"
                    data-active-tab={active}
                    data-slot="editor-content"
                    onScroll={handleScroll}
                >
                    <div style={{ "height": surface.bufferState ? surface.bufferState.rowCount * surface.bufferState.cellHeight : 0 }} />
                </div>
                <div className="w-full h-full grow" ref={divRef}>
                    <GpuTag
                        ref={gpuRef}
                        id={`gpu-${id}`}
                        style={{ width: "100%", height: "100%", backgroundColor: "transparent" }}
                        passthrough={true}
                        hidden={!active}
                        onReady={handleReady}
                    />
                </div>
            </div>
        </div>
    );
}
