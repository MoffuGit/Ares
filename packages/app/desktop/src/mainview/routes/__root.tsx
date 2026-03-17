import { useEffect } from 'react'
import { createRootRoute, Outlet } from '@tanstack/react-router'
import { useApp, useTheme } from '@ares/shared/react'
import { applyTheme } from '../lib/theme'

function RootComponent() {
    const app = useApp();
    const theme = useTheme();

    useEffect(() => {
        if (theme) applyTheme(theme);
    }, [theme]);

    useEffect(() => {
        const onKeyDown = async (e: KeyboardEvent) => {
            const consumed = app.handleKeyDown(e.key, {
                shift: e.shiftKey,
                alt: e.altKey,
                ctrl: e.ctrlKey,
                super: e.metaKey,
                hyper: false,
                meta: false,
                caps_lock: e.getModifierState('CapsLock'),
                num_lock: e.getModifierState('NumLock'),
            });

            if (await consumed) {
                e.preventDefault();
                e.stopPropagation();
            }
        };
        document.addEventListener('keydown', onKeyDown);
        return () => document.removeEventListener('keydown', onKeyDown);
    }, [app]);

    return <Outlet />;
}

export const Route = createRootRoute({
    component: RootComponent,
})
