import { rpc } from '@/lib/app'
import { createFileRoute } from '@tanstack/react-router'
import { useEffect, useRef } from 'react'

export const Route = createFileRoute('/_editor/')({
    component: () => {

        const wgpuRef = useRef<HTMLElement | null>(null)

        useEffect(() => {
            const el = wgpuRef.current as any
            if (!el?.on) return

            const onReady = async (e: CustomEvent) => {
                const rect = el.getBoundingClientRect()
                try {
                    await rpc.request.wgpuTagReady({
                        id: e.detail.id,
                        rect: {
                            x: rect.x,
                            y: rect.y,
                            width: rect.width,
                            height: rect.height,
                        },
                    })
                } catch (err) {
                    console.error('[wgpuTag] wgpuTagReady failed:', err)
                }
            }

            el.on('ready', onReady)

            const sendRect = () => {
                if (!el?.wgpuViewId) return
                const rect = el.getBoundingClientRect()
                rpc.send('wgpuTagRect', {
                    id: el.wgpuViewId,
                    rect: {
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height,
                    },
                })
            }

            let observer: ResizeObserver | undefined
            if ('ResizeObserver' in window) {
                observer = new ResizeObserver(() => sendRect())
                observer.observe(el)
            }

            const onResize = () => sendRect()
            window.addEventListener('resize', onResize)

            return () => {
                window.removeEventListener('resize', onResize)
                observer?.disconnect()
            }
        }, [])

        return (
            <div className="min-w-fit h-full flex flex-col">
                <div className='w-full grow relative'>
                    {/* @ts-expect-error electrobun-wgpu is a custom element */}
                    <electrobun-wgpu
                        ref={wgpuRef}
                        style={{ width: '100%', height: '100%' }}
                    />
                </div>
            </div>
        )
    },
})
