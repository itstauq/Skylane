const { callRpc, getCurrentProps } = require("../runtime");
const { useHostValue } = require("./internal");

function currentPreferenceValue(name) {
  const preferences = getCurrentProps()?.preferences;
  if (!preferences || typeof preferences !== "object" || Array.isArray(preferences)) {
    return undefined;
  }

  return preferences[name];
}

function usePreference(name) {
  const state = useHostValue({
    externalValue: currentPreferenceValue(name),
    write: (value) => callRpc("preferences.setValue", { name, value }),
  });

  return [state.value, state.setValue];
}

module.exports = {
  usePreference,
};
