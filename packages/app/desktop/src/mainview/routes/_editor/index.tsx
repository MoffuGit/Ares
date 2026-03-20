import { BottomBar } from '@/components/bottom-bar'
import { createFileRoute } from '@tanstack/react-router'

export const Route = createFileRoute('/_editor/')({
    component: () => {

        return (
            <div className="min-w-fit h-full flex flex-col">
                <div className='w-full grow'>
                </div>
                <BottomBar />
            </div>
        )
    },
})
