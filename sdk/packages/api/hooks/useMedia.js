const React = require("react");
const { callRpc, subscribeHostEvent } = require("../runtime");
const { useHostMutation, useHostSubscriptionResource } = require("./internal");

const mediaStateEventName = "media.state";
const mediaActions = new Set([
  "play",
  "pause",
  "togglePlayPause",
  "nextTrack",
  "previousTrack",
  "openSourceApp",
]);
const playbackStates = new Set(["playing", "paused", "stopped", "unknown"]);

function createEmptyMediaState() {
  return {
    source: null,
    playbackState: "stopped",
    item: null,
    timeline: null,
    artwork: null,
    availableActions: [],
  };
}

function normalizeString(value) {
  return typeof value === "string" && value.trim() !== "" ? value : undefined;
}

function normalizeNumber(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function normalizeMediaSource(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const id = normalizeString(value.id);
  if (!id) {
    return null;
  }

  return {
    id,
    name: normalizeString(value.name),
    bundleIdentifier: normalizeString(value.bundleIdentifier),
    kind: value.kind === "application" ? "application" : "unknown",
  };
}

function normalizeMediaItem(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  return {
    id: normalizeString(value.id),
    title: normalizeString(value.title),
    artist: normalizeString(value.artist),
    album: normalizeString(value.album),
  };
}

function normalizeMediaTimeline(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const positionSeconds = normalizeNumber(value.positionSeconds);
  const durationSeconds = normalizeNumber(value.durationSeconds);
  if (positionSeconds === undefined && durationSeconds === undefined) {
    return null;
  }

  return {
    positionSeconds,
    durationSeconds,
  };
}

function normalizeMediaArtwork(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const src = normalizeString(value.src);
  const width = normalizeNumber(value.width);
  const height = normalizeNumber(value.height);
  if (src === undefined && width === undefined && height === undefined) {
    return null;
  }

  return {
    src,
    width,
    height,
  };
}

function normalizeAvailableActions(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((action) => typeof action === "string" && mediaActions.has(action));
}

function normalizeMediaState(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return createEmptyMediaState();
  }

  const playbackState = typeof value.playbackState === "string" && playbackStates.has(value.playbackState)
    ? value.playbackState
    : "stopped";

  return {
    source: normalizeMediaSource(value.source),
    playbackState,
    item: normalizeMediaItem(value.item),
    timeline: normalizeMediaTimeline(value.timeline),
    artwork: normalizeMediaArtwork(value.artwork),
    availableActions: normalizeAvailableActions(value.availableActions),
  };
}

function useMedia() {
  const actionMutation = useHostMutation(async (method) => {
    return callRpc(method, {});
  });
  const mediaResource = useHostSubscriptionResource({
    initialData: createEmptyMediaState(),
    load: React.useCallback(() => callRpc("media.getState", {}), []),
    subscribe: React.useCallback((listener) => {
      return subscribeHostEvent(mediaStateEventName, listener);
    }, []),
    normalize: normalizeMediaState,
    onResolved: actionMutation.clearError,
  });

  const invoke = React.useCallback((method) => {
    actionMutation.mutate(method).catch(() => {});
  }, [actionMutation.mutate]);

  return {
    ...mediaResource.data,
    isLoading: mediaResource.isLoading,
    isPending: actionMutation.isPending,
    error: actionMutation.error ?? mediaResource.error,
    refresh: mediaResource.refresh,
    play() {
      invoke("media.play");
    },
    pause() {
      invoke("media.pause");
    },
    togglePlayPause() {
      invoke("media.togglePlayPause");
    },
    nextTrack() {
      invoke("media.nextTrack");
    },
    previousTrack() {
      invoke("media.previousTrack");
    },
    openSourceApp() {
      invoke("media.openSourceApp");
    },
  };
}

module.exports = {
  useMedia,
  normalizeMediaState,
  createEmptyMediaState,
};
