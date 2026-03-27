import React, { useRef, useCallback, useEffect } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag, GpuTagHandle } from "../gpu-tag";
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator } from "../ui/breadcrumb";
import useResizeObserver from '@react-hook/resize-observer'

interface EditorSurfaceProps {
    id: number;
    surface: EditorSurfaceData;
    active: boolean;
}

//NOTE:
//for the scroll, 
//i need to send an rpc msg with the new topRow,
//there an specific behaviour on this scroll,
//the scroll is by row, not by pixel,
//we can follow the pattern that exist on virtual-list
//for adding the scroll watcher, 
//we should send the topRow every time our scroll passes the row tresshold
//but before doing any of this things, the webview needs to know what the size of a row
//the size of a row is the height of a cell, every surface can have a different cell size,
//for this to work the wbeview shoudl always have the surface cell size,
//because there are other parts that we care about a surface state, like the health,
//we should add a new core library event and make it reach the zustand store, 
//you can check the path it takes the buffer state,

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

    const divRef = useRef(null);

    useResizeObserver(divRef, (entry) => {
        if (!surface.gpuSurfaceId) return;
        const content = entry.contentRect;
        rpc.send("gpuTagRect", { id: surface.gpuSurfaceId, rect: { x: content.x, y: content.y, width: content.width, height: content.height } });
    })

    return (
        <div className="w-full flex flex-col grow data-[surface-active=true]:z-10 -z-10 data-[surface-active=true]:visible invisible" data-surface-active={active}>
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
            <div className="w-full grow relative flex px-1.5">
                <div
                    className="absolute top-0 inset-0 w-full h-full overflow-auto data-[active-tab=true]:flex hidden"
                    data-active-tab={active}
                    data-slot="editor-content"
                >
                    <div style={{ "height": surface.bufferState ? surface.bufferState.rowCount * 16 : 0 }} />
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
