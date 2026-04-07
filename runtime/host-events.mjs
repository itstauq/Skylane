export function createHostEventBus() {
  const subscribers = new Map();

  function subscribe(name, listener) {
    if (typeof name !== "string" || name.trim() === "" || typeof listener !== "function") {
      return () => {};
    }

    const key = name.trim();
    let listeners = subscribers.get(key);
    if (!listeners) {
      listeners = new Set();
      subscribers.set(key, listeners);
    }
    listeners.add(listener);

    return () => {
      const currentListeners = subscribers.get(key);
      if (!currentListeners) {
        return;
      }

      currentListeners.delete(listener);
      if (currentListeners.size === 0) {
        subscribers.delete(key);
      }
    };
  }

  function dispatch(name, payload, onResult) {
    if (typeof name !== "string" || name.trim() === "") {
      return;
    }

    const key = name.trim();
    const listeners = subscribers.get(key);
    if (!listeners || listeners.size === 0) {
      return;
    }

    for (const listener of Array.from(listeners)) {
      const result = listener(payload);
      onResult?.(result);
    }
  }

  function clear() {
    subscribers.clear();
  }

  return {
    subscribe,
    dispatch,
    clear,
  };
}
