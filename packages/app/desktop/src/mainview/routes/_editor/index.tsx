import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_editor/')({
    component: () => {

        return (
            <div className="min-w-fit h-full">
            </div>
        )
    },
})
