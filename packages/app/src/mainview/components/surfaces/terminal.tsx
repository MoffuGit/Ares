import { useMemo, useRef } from "react";
import type { TerminalSurface as TerminalSurfaceData } from "@ares/shared";
import { useAppStore } from "@/lib/app";
import { GpuTag } from "../gpu-tag";
import * as Icons from "../ui/icons";
import { useGpuSurface } from "./use-gpu-surface";

interface TerminalSurfaceProps {
    id: number;
    surface: TerminalSurfaceData;
    active: boolean;
}

export function TerminalSurface({ id, surface, active }: TerminalSurfaceProps) {
    const containerRef = useRef<HTMLDivElement | null>(null);
    const project = useAppStore((state) => state.project);
    const { gpuRef, handleReady } = useGpuSurface({ id, surface, active, containerRef });

    const displayCwd = surface.cwd || project?.path || "~";
    const terminalName = useMemo(() => {
        if (displayCwd === "/") return "/";
        const parts = displayCwd.split("/").filter(Boolean);
        return parts.at(-1) ?? "terminal";
    }, [displayCwd]);

    return (
        <div className="w-full flex flex-col grow data-[surface-active=true]:z-10 -z-10 data-[surface-active=true]:visible invisible" data-surface-active={active}>
            <div className="w-full h-8 flex items-center justify-between px-3 text-xs">
                <div className="min-w-0 flex items-center gap-2">
                    <Icons.Terminal className="size-4 shrink-0 text-muted-foreground" />
                    <span className="shrink-0 font-medium text-foreground">{terminalName}</span>
                    <span className="truncate font-mono text-[11px] text-muted-foreground">{displayCwd}</span>
                </div>
                <span className="shrink-0 text-[11px] uppercase tracking-[0.18em] text-muted-foreground/80">Shell</span>
            </div>
            <div className="w-full grow px-4 pb-4">
                <div
                    ref={containerRef}
                    className="w-full h-full grow overflow-hidden rounded-lg border border-border/60 bg-background/80 shadow-sm"
                    data-slot="terminal-content"
                >
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
