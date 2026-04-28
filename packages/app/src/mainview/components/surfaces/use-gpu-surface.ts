import { rpc, useAppStore } from "@/lib/app";
import type { Surface } from "@ares/shared";
import { useCallback, useEffect, useRef, type RefObject } from "react";
import type { GpuTagHandle } from "../gpu-tag";

type RectLike = Pick<DOMRectReadOnly, "x" | "y" | "width" | "height">;

type UseGpuSurfaceOptions<TSurface extends Surface> = {
    id: number;
    surface: TSurface;
    active: boolean;
    containerRef: RefObject<HTMLElement | null>;
    scrollRef?: RefObject<HTMLElement | null>;
    mouseRef?: RefObject<HTMLElement | null>;
    onReadySuccess?: (gpuSurfaceId: number) => void | Promise<void>;
};

function toGpuRect(rect: RectLike) {
    return {
        x: rect.x,
        y: rect.y,
        width: rect.width,
        height: rect.height,
    };
}

export function useGpuSurface<TSurface extends Surface>({
    id,
    surface,
    active,
    containerRef,
    scrollRef,
    mouseRef,
    onReadySuccess,
}: UseGpuSurfaceOptions<TSurface>) {
    const gpuRef = useRef<GpuTagHandle>(null);

    const handleReady = useCallback(async (gpuSurfaceId: number) => {
        useAppStore.getState().setGpuSurfaceId(id, gpuSurfaceId);

        const rectElement = containerRef.current ?? gpuRef.current?.element;
        if (!rectElement) return;

        try {
            const res = await rpc.request.gpuTagReady({
                id: gpuSurfaceId,
                rect: toGpuRect(rectElement.getBoundingClientRect()),
                surface,
            });

            if (res.success) {
                await onReadySuccess?.(gpuSurfaceId);
            }
        } catch (err) {
            console.error("[GpuTag] gpuTagReady failed:", err);
        }
    }, [containerRef, id, onReadySuccess, surface]);

    useEffect(() => {
        gpuRef.current?.toggleHidden(!active);

        if (surface.gpuSurfaceId != null) {
            rpc.send("gpuTagVisibility", { id: surface.gpuSurfaceId, visible: active });
        }
    }, [active, surface.gpuSurfaceId]);

    useEffect(() => {
        const target = scrollRef?.current;
        if (!target) return;

        const handleScroll = () => {
            if (!surface.gpuSurfaceId || !surface.surfaceState) return;
            const cellHeight = surface.surfaceState.cellHeight;
            if (cellHeight <= 0) return;
            const row = Math.ceil(target.scrollTop / cellHeight);
            rpc.send("surfaceScrollTo", { surfaceId: surface.gpuSurfaceId, row });
        };

        target.addEventListener("scroll", handleScroll, { passive: true });
        return () => target.removeEventListener("scroll", handleScroll);
    }, [scrollRef, surface.gpuSurfaceId, surface.surfaceState]);

    useEffect(() => {
        const target = mouseRef?.current ?? containerRef.current;
        if (!target) return;

        const sendMouseEvent = (e: MouseEvent) => {
            if (!surface.gpuSurfaceId) return;
            const rect = target.getBoundingClientRect();
            let mods = 0;
            if (e.shiftKey) mods |= 1 << 0;
            if (e.altKey) mods |= 1 << 1;
            if (e.ctrlKey) mods |= 1 << 2;
            if (e.metaKey) mods |= 1 << 3;
            rpc.send("surfaceMouseEvent", {
                surfaceId: surface.gpuSurfaceId,
                type: e.type as "mousedown" | "mousemove" | "mouseup",
                x: e.clientX - rect.left,
                y: e.clientY - rect.top,
                button: e.button,
                mods,
            });
        };

        target.addEventListener("mousedown", sendMouseEvent);
        target.addEventListener("mousemove", sendMouseEvent);
        target.addEventListener("mouseup", sendMouseEvent);

        return () => {
            target.removeEventListener("mousedown", sendMouseEvent);
            target.removeEventListener("mousemove", sendMouseEvent);
            target.removeEventListener("mouseup", sendMouseEvent);
        };
    }, [mouseRef, containerRef, surface.gpuSurfaceId]);

    return { gpuRef, handleReady };
}
