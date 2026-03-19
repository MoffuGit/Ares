import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_editor/')({
    component: () => {
        // const mode = useMode()
        // const globalKeymaps = useScopedKeymaps('global')
        // const editorKeymaps = useScopedKeymaps('editor')

        return (
            <div className="p-4 space-y-2">
            </div>
        )
    },
})
// <p className="text-sm font-medium">Mode: {mode}</p>
// <p className="text-sm font-medium">Global Keymaps ({Object.keys(globalKeymaps).length}):</p>
// <ul className="text-xs font-mono space-y-1">
//     {Object.entries(globalKeymaps).map(([sequence, action]) => (
//         <li key={sequence}>
//             <span className="text-muted-foreground">{sequence}</span>
//             {' → '}
//             <span>{action}</span>
//         </li>
//     ))}
// </ul>
// <p className="text-sm font-medium">Editor Keymaps ({Object.keys(editorKeymaps).length}):</p>
// <ul className="text-xs font-mono space-y-1">
//     {Object.entries(editorKeymaps).map(([sequence, action]) => (
//         <li key={sequence}>
//             <span className="text-muted-foreground">{sequence}</span>
//             {' → '}
//             <span>{action}</span>
//         </li>
//     ))}
// </ul>
