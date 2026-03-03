import { useEffect } from 'react'
import { createRootRoute, Outlet } from '@tanstack/react-router'
import { useTheme } from '@ares/shared/react'
import { applyTheme } from '../lib/theme'

function RootComponent() {
    const theme = useTheme();

    useEffect(() => {
        if (theme) applyTheme(theme);
    }, [theme]);

    return <Outlet />;
}

export const Route = createRootRoute({
    component: RootComponent,
})
