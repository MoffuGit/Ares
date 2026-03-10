import { createSignal, For, onMount, onCleanup } from "solid-js";
import { render } from "../src/index";
import type { BoxElement } from "@ares/tui-core/elements";

const COLORS = ["#e74c3c", "#3498db", "#2ecc71", "#f1c40f", "#9b59b6", "#1abc9c", "#e67e22", "#00d9ff"];

function Counter() {
    const [count, setCount] = createSignal(1);

    onMount(() => {
        const timer = setInterval(() => {
            setCount((c) => c + 1);
            console.log("[timer] count set to", count());
        }, 5000);
        onCleanup(() => clearInterval(timer));
    });

    return (
        <box
            flexGrow={1}
            flexDirection="column"
            justifyContent="center"
            alignItems="center"
            bg="#1a1a2e"
            fg="#e0e0e0"
            onKeydown={(e) => {
                const data = e.data as { codepoint: number; mods: number };
                if (data.codepoint === 99 && (data.mods & 4) !== 0) {
                    dispose();
                    process.exit(0);
                }
            }}
        >
            <box
                bg="#333355"
                fg="#00d9ff"
                style={{
                    width: { point: 100 },
                    height: { point: 1 }
                }}
            >
                Count: {count()}
            </box>
            <box flexDirection="row" flexWrap="wrap" style={{ width: { point: 100 } }}>
                <For each={Array.from({ length: count() }, (_, i) => i)}>
                    {(i) => (
                        <box
                            bg={COLORS[i % COLORS.length]}
                            fg="#ffffff"
                            style={{ width: { point: 3 }, height: { point: 1 } }}
                        >
                            {` ${i + 1} `}
                        </box>
                    )}
                </For>
            </box>
            <box
                ref={(el: BoxElement) => el.focus()}
                bg="#333355"
                fg="#ffffff"
                width={{ point: 100 }}
                style={{
                    padding: { all: { point: 1 } },
                }}
                onKeydown={(e) => {
                    const data = e.data as { codepoint: number };
                    if (data.codepoint === 32) setCount((c) => c + 1);
                    if (data.codepoint === 114) setCount(0);
                }}
            >
                [Space] increment · [R] reset
            </box>
        </box>
    );
}

const dispose = render(() => <Counter />);
