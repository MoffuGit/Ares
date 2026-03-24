import { useEffect, useRef } from "react";
import { rpc, useAppStore } from "@/lib/app";
import type { View } from "@ares/shared";

interface GpuTagProps {
    tabId: number;
    view: View;
}

export function GpuTag({ tabId, view }: GpuTagProps) {
    const GpuRef = useRef<HTMLElement | null>(null);

    useEffect(() => {
        const el = GpuRef.current as any;
        if (!el?.on) return;

        const onReady = async (e: CustomEvent) => {
            const gpuViewId = e.detail.id as number;
            useAppStore.getState().setGpuViewId(tabId, gpuViewId);

            const rect = el.getBoundingClientRect();
            try {
                const res = await rpc.request.gpuTagReady({
                    id: gpuViewId,
                    rect: {
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height,
                    },
                    view,
                });
                if (res.success) {
                    const { tabs } = useAppStore.getState();
                    const tab = tabs.find((t) => t.id === tabId);
                    if (tab?.pendingEntryId != null) {
                        rpc.send("selectEntry", { viewId: gpuViewId, id: tab.pendingEntryId });
                        useAppStore.setState({
                            tabs: tabs.map((t) => t.id === tabId ? { ...t, pendingEntryId: undefined } : t),
                        });
                    }
                }
            } catch (err) {
                console.error("[wgpuTag] wgpuTagReady failed:", err);
            }
        };

        el.on("ready", onReady);

        const sendRect = () => {
            if (!el?.wgpuViewId) return;
            const rect = el.getBoundingClientRect();
            rpc.send("gpuTagRect", {
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
            id={`gpu-${tabId}`}
            ref={GpuRef}
            style={{ width: "100%", height: "100%", "backgroundColor": "transparent" }}
        />
    );
}
