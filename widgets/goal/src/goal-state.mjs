export function normalizeGoalDraft(value) {
  return typeof value === "string" ? value : "";
}

export function normalizeDurationDraft(value) {
  return typeof value === "string" ? value : "";
}

export function parseDurationMinutes(value) {
  const normalized = normalizeDurationDraft(value).trim().toLowerCase();
  if (!normalized) {
    return null;
  }

  if (/^\d+$/.test(normalized)) {
    const minutes = Number.parseInt(normalized, 10);
    return Number.isFinite(minutes) && minutes > 0 ? minutes : null;
  }

  const match = normalized.match(
    /^(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours)$/
  );
  if (!match) {
    return null;
  }

  const amount = Number.parseFloat(match[1]);
  if (!Number.isFinite(amount) || amount <= 0) {
    return null;
  }

  const unit = match[2];
  if (unit.startsWith("h")) {
    return Math.round(amount * 60);
  }

  return Math.round(amount);
}

export function formatDurationLabel(minutes) {
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return "";
  }

  if (minutes < 60) {
    return `${minutes} min`;
  }

  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  if (remainder === 0) {
    return `${hours} hr`;
  }

  return `${hours} hr ${remainder} min`;
}

export function formatDurationCompact(minutes) {
  if (!Number.isFinite(minutes) || minutes <= 0) {
    return "";
  }

  if (minutes < 60) {
    return `${minutes}m`;
  }

  const hours = Math.floor(minutes / 60);
  const remainder = minutes % 60;
  if (remainder === 0) {
    return `${hours}h`;
  }

  return `${hours}h ${remainder}m`;
}

export function createGoalSession({ goal, durationInput, now = Date.now() }) {
  const normalizedGoal = normalizeGoalDraft(goal).trim();
  if (!normalizedGoal) {
    return null;
  }

  const normalizedDurationInput = normalizeDurationDraft(durationInput).trim();
  const durationMinutes = parseDurationMinutes(normalizedDurationInput);
  if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
    return null;
  }

  return {
    goal: normalizedGoal,
    durationInput: normalizedDurationInput,
    durationMinutes,
    startedAt: now,
  };
}

export function normalizeGoalSession(value, now = Date.now()) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }

  const goal = normalizeGoalDraft(value.goal).trim();
  if (!goal) {
    return null;
  }

  const rawDurationInput = normalizeDurationDraft(value.durationInput).trim();
  const storedDurationMinutes =
    Number.isFinite(value.durationMinutes) && value.durationMinutes > 0
      ? Math.round(value.durationMinutes)
      : null;
  const durationMinutes = parseDurationMinutes(rawDurationInput) ?? storedDurationMinutes;
  if (!Number.isFinite(durationMinutes) || durationMinutes <= 0) {
    return null;
  }

  const startedAt =
    Number.isFinite(value.startedAt) && value.startedAt > 0 ? value.startedAt : now;

  return {
    goal,
    durationInput: rawDurationInput || formatDurationLabel(durationMinutes),
    durationMinutes,
    startedAt,
  };
}

export function progressForSession(session, now = Date.now()) {
  if (!session || !Number.isFinite(session.durationMinutes) || session.durationMinutes <= 0) {
    return null;
  }

  const totalMs = session.durationMinutes * 60_000;
  const elapsedMs = Math.max(0, now - session.startedAt);
  const remainingMs = totalMs - elapsedMs;
  const progress = Math.min(1, elapsedMs / totalMs);

  return {
    totalMs,
    elapsedMs,
    remainingMs,
    progress,
    isOvertime: remainingMs < 0,
  };
}

function wholeMinutes(ms, rounding) {
  const absoluteMs = Math.abs(ms);
  const method = rounding === "floor" ? Math.floor : Math.ceil;
  return Math.max(0, method(absoluteMs / 60_000));
}

export function formatRemainingLabel(remainingMs) {
  if (!Number.isFinite(remainingMs)) {
    return "";
  }

  if (remainingMs <= 0) {
    const overtimeMinutes = wholeMinutes(remainingMs, "ceil");
    return overtimeMinutes > 0 ? `Over by ${overtimeMinutes} min` : "Time is up";
  }

  const minutes = wholeMinutes(remainingMs, "ceil");
  return `${minutes} min left`;
}

export function formatElapsedLabel(elapsedMs) {
  if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) {
    return "Just started";
  }

  const minutes = wholeMinutes(elapsedMs, "floor");
  return `${Math.max(1, minutes)} min elapsed`;
}
