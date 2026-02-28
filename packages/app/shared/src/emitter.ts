export type EventMap = Record<string, unknown[]>;

export class Emitter<T extends EventMap> {
  private listeners = new Map<keyof T, Set<(...args: any[]) => void>>();

  on<K extends keyof T>(event: K, fn: (...args: T[K]) => void): void {
    let set = this.listeners.get(event);
    if (!set) {
      set = new Set();
      this.listeners.set(event, set);
    }
    set.add(fn);
  }

  off<K extends keyof T>(event: K, fn: (...args: T[K]) => void): void {
    this.listeners.get(event)?.delete(fn);
  }

  emit<K extends keyof T>(event: K, ...args: T[K]): void {
    const set = this.listeners.get(event);
    if (set) {
      for (const fn of set) fn(...args);
    }
  }

  removeAll(): void {
    this.listeners.clear();
  }
}
