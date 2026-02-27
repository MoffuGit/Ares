import { createContext, useContext, useEffect, useMemo, useSyncExternalStore } from "react";
import type { AresBackend } from "../backend.ts";
import { createAresStore } from "../store.ts";

type Store = ReturnType<typeof createAresStore>;

const AresContext = createContext<Store | null>(null);

export function AresProvider(props: {
  backend: AresBackend;
  children: React.ReactNode;
}) {
  const store = useMemo(() => createAresStore(props.backend), [props.backend]);

  useEffect(() => {
    store.ensureStarted();
    return () => store.destroy();
  }, [store]);

  return (
    <AresContext.Provider value={store}>{props.children}</AresContext.Provider>
  );
}

function useStore(): Store {
  const store = useContext(AresContext);
  if (!store) throw new Error("Missing <AresProvider>");
  return store;
}

export function useSettings() {
  const store = useStore();
  return useSyncExternalStore(store.subscribe, store.getSnapshot, store.getSnapshot);
}
