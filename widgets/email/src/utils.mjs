export function withAlpha(color, alpha) {
  if (typeof color !== "string") {
    return color;
  }

  const normalized = color.startsWith("#") ? color.slice(1) : color;
  if (normalized.length < 6) {
    return color;
  }

  return `#${normalized.slice(0, 6)}${alpha}`;
}

export function normalizePreferenceText(value) {
  return typeof value === "string" ? value.trim() : "";
}

export function isAbortError(error) {
  return error?.name === "AbortError";
}

export function sleep(ms, signal) {
  if (signal?.aborted) {
    return Promise.reject(new DOMException("The operation was aborted.", "AbortError"));
  }

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(resolve, ms);
    const abort = () => {
      clearTimeout(timeout);
      reject(new DOMException("The operation was aborted.", "AbortError"));
    };

    signal?.addEventListener("abort", abort, { once: true });
  });
}

export function normalizeEmailMessages(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((message) => {
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      return [];
    }

    const id = typeof message.id === "string" ? message.id.trim() : "";
    const sender = typeof message.sender === "string" ? message.sender.trim() : "";
    const subject = typeof message.subject === "string" ? message.subject.trim() : "";
    const fallbackAvatar = sender.slice(0, 1).toUpperCase();
    const avatar = typeof message.avatar === "string"
      ? message.avatar.trim().slice(0, 1).toUpperCase()
      : fallbackAvatar;
    const tint = typeof message.tint === "string" && message.tint.trim()
      ? message.tint.trim()
      : "#FA757A";

    if (!id || !sender || !subject) {
      return [];
    }

    const normalized = {
      id,
      sender,
      subject,
      avatar: avatar || fallbackAvatar || "?",
      tint,
      unread: message.unread !== false,
    };
    const uid = typeof message.uid === "string" ? message.uid.trim() : "";
    if (uid) {
      normalized.uid = uid;
    }

    return [normalized];
  });
}

export function getInboxViewState(inbox, messages) {
  if (inbox.isLoading) {
    return { type: "panel", title: "Checking inbox" };
  }

  if (inbox.error) {
    return {
      type: "panel",
      title: "Unable to load mail",
      detail: inbox.error.message,
    };
  }

  if (inbox.data?.needsConfiguration) {
    return { type: "setup" };
  }

  if (messages.length === 0) {
    return { type: "panel", title: "No unread mail" };
  }

  return { type: "messages", messages };
}
