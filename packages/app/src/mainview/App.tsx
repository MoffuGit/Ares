import { useAppStore } from "@/lib/app"
import {
    SidebarProvider,
    SidebarInset,
} from "@/components/ui/sidebar"
import { TooltipProvider } from '@/components/ui/tooltip'
import { AppSidebar } from '@/components/app-sidebar'
import { EmptyState } from '@/components/empty-state'
import { TabContent } from '@/components/tab-content'
import { BottomBar, Theme, TopBar } from './components'

function App() {
    const project = useAppStore((s) => s.project);
    const tabs = useAppStore((s) => s.tabs);
    const activeTabId = useAppStore((s) => s.activeTabId);
    const sidebarOpen = useAppStore((s) => s.sidebarOpen);
    const { setSidebarOpen } = useAppStore.getState();

    return (
        <TooltipProvider>
            <Theme />
            <TopBar />
            {project ? (
                <>
                    <SidebarProvider open={sidebarOpen} onOpenChange={setSidebarOpen}>
                        <div className='flex-1 flex flex-row bg-sidebar'>
                            <AppSidebar />
                            <SidebarInset className='rounded-lg bg-muted shadow-inset flex flex-col dark:border border-border/50'>
                                <div className='isolate relative grow w-full'>
                                    {tabs.map((tab) => (
                                        <TabContent key={tab.id} tab={tab} active={tab.id === activeTabId} />
                                    ))}
                                </div>
                            </SidebarInset>
                        </div>
                    </SidebarProvider>
                    <BottomBar />
                </>
            ) : (
                <EmptyState />
            )}
        </TooltipProvider>
    );
}

export default App
