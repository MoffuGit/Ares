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
    onResize?: (viewId: number, rect: Rect) => void;
}

type Rect = { x: number; y: number; width: number; height: number };

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
            onResize
        },
        ref,
    ) {
        const elRef = useRef<HTMLElement | null>(null);
        const onReadyRef = useRef(onReady);
        const hiddenRef = useRef(hidden);
        const onResizeRef = useRef(onResize);
        onReadyRef.current = onReady;
        onResizeRef.current = onResize
        hiddenRef.current = hidden;

        const getEl = useCallback(() => {
            return elRef.current as (HTMLElement & {
                wgpuViewId: number | null;
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
                return getEl()?.wgpuViewId ?? null;
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
            if (el?.wgpuViewId == null) return;
            el.toggleHidden(hidden);
        }, [hidden, getEl]);
          useEffect(() => {
      const el = getEl();
      if (!el) return;

      const observer = new ResizeObserver(() => {
          const viewId = el.wgpuViewId;
          if (viewId == null) return;
          const rect = el.getBoundingClientRect();
          onResizeRef.current?.(viewId, {
              x: rect.x,
              y: rect.y,
              width: rect.width,
              height: rect.height,
          });
      });
      observer.observe(el);

      return () => observer.disconnect();
  }, [getEl]);

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
