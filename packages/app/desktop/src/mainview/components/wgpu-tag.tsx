import { useEffect, useRef } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { View } from "@ares/shared";

interface WgpuTagProps {
    tabId: number;
    view: View;
}

export function WgpuTag({ tabId, view }: WgpuTagProps) {
    const wgpuRef = useRef<HTMLElement | null>(null);

    useEffect(() => {
        const el = wgpuRef.current as any;
        if (!el?.on) return;

        const onReady = async (e: CustomEvent) => {
            const gpuViewId = e.detail.id as number;
            useAppStore.getState().setGpuViewId(tabId, gpuViewId);

            const rect = el.getBoundingClientRect();
            try {
                await rpc.request.wgpuTagReady({
                    id: gpuViewId,
                    rect: {
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height,
                    },
                    view,
                });
            } catch (err) {
                console.error("[wgpuTag] wgpuTagReady failed:", err);
            }
        };

        el.on("ready", onReady);

        const sendRect = () => {
            if (!el?.wgpuViewId) return;
            const rect = el.getBoundingClientRect();
            rpc.send("wgpuTagRect", {
                id: el.wgpuViewId,
                rect: {
                    x: rect.x,
                    y: rect.y,
                    width: rect.width,
                    height: rect.height,
                },
            });
        };

        let observer: ResizeObserver | undefined;
        if ("ResizeObserver" in window) {
            observer = new ResizeObserver(() => sendRect());
            observer.observe(el);
        }

        const onResize = () => sendRect();
        window.addEventListener("resize", onResize);

        return () => {
            window.removeEventListener("resize", onResize);
            observer?.disconnect();
        };
    }, [tabId, view]);

    return (
        // @ts-expect-error electrobun-wgpu is a custom element
        <electrobun-wgpu
            ref={wgpuRef}
            style={{ width: "100%", height: "100%" }}
        />
    );
}
