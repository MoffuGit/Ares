import React, { useRef } from "react";
import { rpc } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag } from "../gpu-tag";
import { Breadcrumb, BreadcrumbList, BreadcrumbItem, BreadcrumbPage, BreadcrumbSeparator } from "../ui/breadcrumb";
import { FileIcon } from "../file-icons";
import { useGpuSurface } from "./use-gpu-surface";

interface EditorSurfaceProps {
    id: number;
    surface: EditorSurfaceData;
    active: boolean;
}

export function EditorSurface({ id, surface, active }: EditorSurfaceProps) {
    const containerRef = useRef<HTMLDivElement | null>(null);
    const scrollRef = useRef<HTMLDivElement | null>(null);
    const mouseRef = useRef<HTMLDivElement | null>(null);
    const { gpuRef, handleReady } = useGpuSurface({
        id,
        surface,
        active,
        containerRef,
        scrollRef,
        mouseRef,
        onReadySuccess: (gpuSurfaceId) => {
            if (surface.entry != null) {
                rpc.send("selectSurfaceEntry", { surfaceId: gpuSurfaceId, id: surface.entry.id });
            }
        },
    });

    return (
        <div className="w-full flex flex-col grow data-[surface-active=true]:z-10 -z-10 data-[surface-active=true]:visible invisible" data-surface-active={active}>
            <div className="w-full h-8 flex items-center justify-start px-2 tracking-wide">
                {surface.entry && (() => {
                    const parts = surface.entry.path.split("/").slice(1);
                    return (
                        <Breadcrumb>
                            <BreadcrumbList>
                                {parts.map((part, i) => (
                                    <React.Fragment key={i}>
                                        {i > 0 && <BreadcrumbSeparator />}
                                        <BreadcrumbItem>
                                            {i === parts.length - 1 && surface.entry && (
                                                <BreadcrumbPage>
                                                    <FileIcon entry={surface.entry} />
                                                </BreadcrumbPage>
                                            )}
                                            <BreadcrumbPage>
                                                {part}
                                            </BreadcrumbPage>
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
                    className="absolute inset-0 overflow-auto data-[active-tab=true]:flex hidden"
                    data-slot="editor-content"
                    data-active-tab={active}
                    ref={scrollRef}
                >
                    <div
                        className="sticky top-0 w-full h-full px-4"
                    >
                        <div
                            className="w-full h-full"
                            ref={mouseRef}
                        />
                    </div>
                    <div style={{
                        height: surface.editorState && surface.surfaceState
                            ? surface.editorState.rowCount * surface.surfaceState.cellHeight
                            : 0,
                    }} />
                </div>
                <div className="w-full h-full grow" ref={containerRef}>
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
