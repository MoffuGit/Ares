import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Electroview } from "electrobun/view";
import { useAppStore, rpc } from "./lib/app.ts";
import "./index.css";
import App from "./App";

export const electroview = new Electroview({ rpc });

useAppStore.getState().initialLoad();

createRoot(document.getElementById("root")!).render(
    <StrictMode>
        <App />
    </StrictMode>,
);
