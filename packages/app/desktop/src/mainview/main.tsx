import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AppProvider } from "@ares/shared/react";
import { WebviewApp } from "./lib/app.ts";
import { Electroview } from "electrobun/view";
import "./index.css";
import App from "./App";

const app = new WebviewApp();
export const electroview = new Electroview({ rpc: app.electroview });
app.loadSettings().then(() => {
    createRoot(document.getElementById("root")!).render(
    <StrictMode>
        <AppProvider app={app}>
            <App />
        </AppProvider>
    </StrictMode>,
    );
});
