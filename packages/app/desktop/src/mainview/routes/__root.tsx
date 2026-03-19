import { createRootRoute, Outlet } from '@tanstack/react-router'
import { useEffect } from 'react'
import { keymapHandler } from '@/lib/app'

function RootComponent() {
    useEffect(() => {
        const onKeyDown = (e: KeyboardEvent) => {
            const consumed = keymapHandler.handleKeyDown(e.key, {
                shift: e.shiftKey,
                alt: e.altKey,
                ctrl: e.ctrlKey,
                super: e.metaKey,
                hyper: false,
                meta: false,
                caps_lock: e.getModifierState('CapsLock'),
                num_lock: e.getModifierState('NumLock'),
            });

            if (consumed) {
                e.preventDefault();
                e.stopPropagation();
            }
        };
        document.addEventListener('keydown', onKeyDown);
        return () => document.removeEventListener('keydown', onKeyDown);
    }, []);

    return <Outlet />;
}

export const Route = createRootRoute({
    component: RootComponent,
})
