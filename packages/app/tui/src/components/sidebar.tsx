import { createContext } from "solid-js";

const SidebarContext = createContext(null);
function SidebarProvider({
}) {
    <SidebarContext.Provider value={null}>
    </SidebarContext.Provider>
}
