import { useRef } from "react";
import { rpc } from "@/lib/app";
import type { EditorSurface as EditorSurfaceData } from "@ares/shared";
import { GpuTag } from "../gpu-tag";
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
            <div className="w-full grow relative flex p-2">
                <div
                    className="absolute inset-0 overflow-auto data-[active-tab=true]:flex hidden"
                    data-slot="editor-content"
                    data-active-tab={active}
                    ref={scrollRef}
                >
                    <div
                        className="sticky top-0 w-full h-full p-2"
                    >
                        <div
                            className="w-full h-full outline-none"
                            ref={mouseRef}
                            tabIndex={active ? 0 : -1}
                            onMouseDown={(event) => {
                                event.currentTarget.focus();
                            }}
                            onKeyDown={(event) => {
                                if (surface.gpuSurfaceId == null) return;
                                if (event.altKey || event.ctrlKey || event.metaKey) return;

                                event.preventDefault();

                                let mods: number = 0;
                                if (event.shiftKey) mods |= 1 << 0;
                                if (event.altKey) mods |= 1 << 1;
                                if (event.ctrlKey) mods |= 1 << 2;
                                if (event.metaKey) mods |= 1 << 3;

                                rpc.send("surfaceKeyEvent", {
                                    id: surface.gpuSurfaceId,
                                    key: event.key,
                                    code: event.code,
                                    mods,
                                    repeat: event.repeat,
                                });
                            }}
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
