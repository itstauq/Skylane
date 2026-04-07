function runtime() {
  if (!globalThis.__NOTCH_RUNTIME__) {
    throw new Error("@notchapp/api must run inside the Notch widget runtime");
  }

  return globalThis.__NOTCH_RUNTIME__;
}

module.exports = {
  LocalStorage: {
    getItem(key) {
      return runtime().localStorage.getItem(key);
    },
    setItem(key, value) {
      return runtime().localStorage.setItem(key, value);
    },
    removeItem(key) {
      return runtime().localStorage.removeItem(key);
    },
    allItems() {
      return runtime().localStorage.allItems();
    },
  },
  getPreferenceValues() {
    const preferences = runtime().getCurrentProps()?.preferences;
    if (!preferences || typeof preferences !== "object" || Array.isArray(preferences)) {
      return {};
    }

    return structuredClone(preferences);
  },
  getTheme() {
    const theme = runtime().getCurrentProps()?.theme;
    if (!theme || typeof theme !== "object" || Array.isArray(theme)) {
      return {};
    }

    return structuredClone(theme);
  },
  setPreferenceValue(name, value) {
    return runtime().callRpc("preferences.setValue", { name, value });
  },
  listCameras() {
    return runtime().callRpc("camera.listDevices", {});
  },
  selectCamera(id) {
    return runtime().callRpc("camera.selectDevice", { id });
  },
  getCurrentProps: () => runtime().getCurrentProps(),
  callRpc: (method, params) => runtime().callRpc(method, params),
  subscribeHostEvent: (name, listener) => {
    const subscribe = runtime().subscribeHostEvent;
    if (typeof subscribe !== "function") {
      return () => {};
    }

    return subscribe(name, listener);
  },
};
