import { createFileRoute } from '@tanstack/react-router'
import { useScopedKeymaps, useMode } from '@ares/shared/react'

export const Route = createFileRoute('/_editor/')({
    component: () => {
        const mode = useMode()
        const globalKeymaps = useScopedKeymaps('global')
        const editorKeymaps = useScopedKeymaps('editor')

        return (
            <div className="p-4 space-y-2">
                <p className="text-sm font-medium">Mode: {mode}</p>
                <p className="text-sm font-medium">Global Keymaps ({globalKeymaps.length}):</p>
                <ul className="text-xs font-mono space-y-1">
                    {globalKeymaps.map((b, i) => (
                        <li key={i}>
                            <span className="text-muted-foreground">{b.sequence}</span>
                            {' → '}
                            <span>{b.action}</span>
                        </li>
                    ))}
                </ul>
                <p className="text-sm font-medium">Editor Keymaps ({editorKeymaps.length}):</p>
                <ul className="text-xs font-mono space-y-1">
                    {editorKeymaps.map((b, i) => (
                        <li key={i}>
                            <span className="text-muted-foreground">{b.sequence}</span>
                            {' → '}
                            <span>{b.action}</span>
                        </li>
                    ))}
                </ul>
            </div>
        )
    },
})
