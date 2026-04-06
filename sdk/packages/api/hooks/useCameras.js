const { callRpc, getCurrentProps } = require("../runtime");
const { useHostResource, useHostValue } = require("./internal");

const cameraPreferenceName = "cameraDeviceId";

function normalizeCameraItems(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((item) => {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      return [];
    }

    if (typeof item.id !== "string" || item.id.trim() === "") {
      return [];
    }

    if (typeof item.name !== "string" || item.name.trim() === "") {
      return [];
    }

    return [{
      id: item.id,
      name: item.name,
      selected: item.selected === true,
      unavailable: item.unavailable === true,
    }];
  });
}

function selectedCameraIDFromProps() {
  const preferences = getCurrentProps()?.preferences;
  if (!preferences || typeof preferences !== "object" || Array.isArray(preferences)) {
    return undefined;
  }

  const value = preferences[cameraPreferenceName];
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function resolveSelectedCameraID(items) {
  const selectedFromProps = selectedCameraIDFromProps();
  if (selectedFromProps) {
    return selectedFromProps;
  }

  return items.find((item) => item.selected)?.id;
}

function useCameras() {
  const resource = useHostResource(
    () => callRpc("camera.listDevices", {}),
    [],
    { initialData: [] }
  );
  const normalizedItems = normalizeCameraItems(resource.data);
  const selection = useHostValue({
    externalValue: resolveSelectedCameraID(normalizedItems),
    write: (id) => callRpc("camera.selectDevice", { id }),
  });

  return {
    items: normalizedItems.map((item) => ({
      id: item.id,
      name: item.name,
      unavailable: item.unavailable === true ? true : undefined,
    })),
    value: selection.value,
    setValue: selection.setValue,
    isLoading: resource.isLoading,
    isPending: selection.isPending,
    error: selection.error ?? resource.error,
    refresh: resource.refresh,
  };
}

module.exports = {
  useCameras,
};
