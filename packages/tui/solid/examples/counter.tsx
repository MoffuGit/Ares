import { createSignal } from "solid-js";
import { render } from "../src/index";
import type { BoxElement } from "@ares/tui-core/elements";

function Counter() {
    const [count, setCount] = createSignal(0);

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
