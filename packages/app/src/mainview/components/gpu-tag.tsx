import {
    useEffect,
    useRef,
    useCallback,
    useImperativeHandle,
    forwardRef,
    type CSSProperties,
} from "react";

export interface GpuTagHandle {
    readonly viewId: number | null;
    readonly element: HTMLElement | null;
    toggleHidden: (value?: boolean) => void;
    toggleTransparent: (value?: boolean) => void;
    togglePassthrough: (value?: boolean) => void;
    syncDimensions: (force?: boolean) => void;
    addMaskSelector: (selector: string) => void;
    removeMaskSelector: (selector: string) => void;
}

export interface GpuTagProps {
    id?: string;
    style?: CSSProperties;
    className?: string;
    transparent?: boolean;
    passthrough?: boolean;
    hidden?: boolean;
    masks?: string;
    onReady?: (viewId: number) => void;
}

export const GpuTag = forwardRef<GpuTagHandle, GpuTagProps>(
    function GpuTag(
        {
            id,
            style,
            className,
            transparent,
            passthrough,
            hidden,
            masks,
            onReady,
        },
        ref,
    ) {
        const elRef = useRef<HTMLElement | null>(null);
        const onReadyRef = useRef(onReady);
        const hiddenRef = useRef(hidden);
        onReadyRef.current = onReady;
        hiddenRef.current = hidden;

        const getEl = useCallback(() => {
            return elRef.current as (HTMLElement & {
                wgpuSurfaceId: number | null;
                toggleHidden: (v?: boolean) => void;
                toggleTransparent: (v?: boolean) => void;
                togglePassthrough: (v?: boolean) => void;
                syncDimensions: (force?: boolean) => void;
                addMaskSelector: (s: string) => void;
                removeMaskSelector: (s: string) => void;
                on: (event: string, listener: (e: CustomEvent) => void) => void;
                off: (event: string, listener: (e: CustomEvent) => void) => void;
            }) | null;
        }, []);

        useImperativeHandle(ref, () => ({
            get viewId() {
                return getEl()?.wgpuSurfaceId ?? null;
            },
            get element() {
                return elRef.current;
            },
            toggleHidden: (value) => getEl()?.toggleHidden(value),
            toggleTransparent: (value) => getEl()?.toggleTransparent(value),
            togglePassthrough: (value) => getEl()?.togglePassthrough(value),
            syncDimensions: (force) => getEl()?.syncDimensions(force),
            addMaskSelector: (selector) => getEl()?.addMaskSelector(selector),
            removeMaskSelector: (selector) => getEl()?.removeMaskSelector(selector),
        }), [getEl]);

        useEffect(() => {
            const el = getEl();
            if (!el?.on) return;

            const handleReady = (e: CustomEvent) => {
                const viewId = e.detail.id as number;
                if (hiddenRef.current) el.toggleHidden(true);
                onReadyRef.current?.(viewId);
            };

            el.on("ready", handleReady);
            return () => el.off("ready", handleReady);
        }, [getEl]);

        useEffect(() => {
            const el = getEl();
            if (el?.wgpuSurfaceId == null) return;
            el.toggleHidden(hidden);
        }, [hidden, getEl]);

        const attrs: Record<string, string | undefined> = {};
        if (transparent) attrs.transparent = "";
        if (passthrough) attrs.passthrough = "";
        if (masks) attrs.masks = masks;

        return (
            // @ts-expect-error electrobun-wgpu is a custom element
            <electrobun-wgpu
                id={id}
                ref={elRef}
                style={style}
                class={className}
                {...attrs}
            />
        );
    },
);
