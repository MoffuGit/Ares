import * as React from "react"
import {
    Sidebar,
    SidebarRail,
} from "@/components/ui/sidebar"
import { FileTree } from "./file-tree"
import { SidebarTabs } from "./sidebar-tabs"
import { useAppStore } from "@/lib/app"
import type { SidebarKind } from "@ares/shared"

const SIDEBAR_SWITCH_DURATION = 200
const SIDEBAR_KIND_ORDER: Record<SidebarKind, number> = {
    filetree: 0,
    tabs: 1,
}

type SidebarTransition = {
    from: SidebarKind
    to: SidebarKind
    direction: "left" | "right"
    active: boolean
}

function getSidebarSwitchDirection(from: SidebarKind, to: SidebarKind) {
    return SIDEBAR_KIND_ORDER[to] > SIDEBAR_KIND_ORDER[from] ? "right" : "left"
}

function renderSidebarPane(kind: SidebarKind) {
    return kind === "tabs" ? <SidebarTabs /> : <FileTree />
}

export function AppSidebar({ ...props }: React.ComponentProps<typeof Sidebar>) {
    const kind = useAppStore((state) => state.sidebarKind)
    const sidebarOpen = useAppStore((state) => state.sidebarOpen)
    const previousKindRef = React.useRef(kind)
    const transitionTimeoutRef = React.useRef<number | null>(null)
    const transitionFrameRef = React.useRef<number | null>(null)
    const [transition, setTransition] = React.useState<SidebarTransition | null>(null)

    React.useLayoutEffect(() => {
        if (transitionTimeoutRef.current != null) {
            window.clearTimeout(transitionTimeoutRef.current)
            transitionTimeoutRef.current = null
        }
        if (transitionFrameRef.current != null) {
            window.cancelAnimationFrame(transitionFrameRef.current)
            transitionFrameRef.current = null
        }

        if (!sidebarOpen) {
            previousKindRef.current = kind
            setTransition(null)
            return
        }

        if (previousKindRef.current === kind) return

        const nextTransition: SidebarTransition = {
            from: previousKindRef.current,
            to: kind,
            direction: getSidebarSwitchDirection(previousKindRef.current, kind),
            active: false,
        }

        previousKindRef.current = kind
        setTransition(nextTransition)
        transitionFrameRef.current = window.requestAnimationFrame(() => {
            setTransition((current) => current?.to === nextTransition.to
                ? { ...current, active: true }
                : current)
            transitionFrameRef.current = null
        })
        transitionTimeoutRef.current = window.setTimeout(() => {
            setTransition((current) => current?.to === nextTransition.to ? null : current)
            transitionTimeoutRef.current = null
        }, SIDEBAR_SWITCH_DURATION)
    }, [kind, sidebarOpen])

    React.useEffect(() => {
        return () => {
            if (transitionTimeoutRef.current != null) {
                window.clearTimeout(transitionTimeoutRef.current)
            }
            if (transitionFrameRef.current != null) {
                window.cancelAnimationFrame(transitionFrameRef.current)
            }
        }
    }, [])

    const switchStyle = React.useMemo(() => {
        return {
            "--sidebar-switch-duration": `${SIDEBAR_SWITCH_DURATION}ms`,
            "--sidebar-switch-offset": "20%",
        } as React.CSSProperties
    }, [])

    return (
        <Sidebar {...props}>
            <div
                className="relative flex min-h-0 flex-1 overflow-hidden"
                style={switchStyle}
            >
                {transition ? (
                    <>
                        <div
                            className="sidebar-switch-pane"
                            data-active={transition.active}
                            data-direction={transition.direction}
                            data-phase="exit"
                        >
                            {renderSidebarPane(transition.from)}
                        </div>
                        <div
                            className="sidebar-switch-pane"
                            data-active={transition.active}
                            data-direction={transition.direction}
                            data-phase="enter"
                        >
                            {renderSidebarPane(transition.to)}
                        </div>
                    </>
                ) : (
                    <div className="relative flex size-full min-h-0 flex-col">
                        {renderSidebarPane(kind)}
                    </div>
                )}
            </div>
            <SidebarRail />
        </Sidebar>
    )
}
