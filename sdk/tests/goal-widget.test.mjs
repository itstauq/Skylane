import assert from "node:assert/strict";
import { test } from "node:test";

import {
  createGoalSession,
  formatDurationLabel,
  formatElapsedLabel,
  formatRemainingLabel,
  normalizeDurationDraft,
  normalizeGoalDraft,
  normalizeGoalSession,
  parseDurationMinutes,
  progressForSession,
} from "../../widgets/goal/src/goal-state.mjs";

test("normalize goal and duration drafts keep strings and reject non-strings", () => {
  assert.equal(normalizeGoalDraft("Ship the widget"), "Ship the widget");
  assert.equal(normalizeGoalDraft(42), "");
  assert.equal(normalizeDurationDraft("25 min"), "25 min");
  assert.equal(normalizeDurationDraft(null), "");
});

test("parseDurationMinutes supports common minute and hour inputs", () => {
  assert.equal(parseDurationMinutes("25"), 25);
  assert.equal(parseDurationMinutes("25 min"), 25);
  assert.equal(parseDurationMinutes("1 hr"), 60);
  assert.equal(parseDurationMinutes("1.5h"), 90);
  assert.equal(parseDurationMinutes(""), null);
  assert.equal(parseDurationMinutes("later"), null);
});

test("formatDurationLabel renders minute and hour-based labels", () => {
  assert.equal(formatDurationLabel(25), "25 min");
  assert.equal(formatDurationLabel(60), "1 hr");
  assert.equal(formatDurationLabel(90), "1 hr 30 min");
  assert.equal(formatDurationLabel(null), "");
});

test("createGoalSession trims the goal and stores optional duration metadata", () => {
  const session = createGoalSession({
    goal: "  Finish the host dialog polish  ",
    durationInput: "45 min",
    now: 1000,
  });

  assert.deepEqual(session, {
    goal: "Finish the host dialog polish",
    durationInput: "45 min",
    durationMinutes: 45,
    startedAt: 1000,
  });

  assert.equal(
    createGoalSession({ goal: "   ", durationInput: "25 min", now: 1000 }),
    null
  );
});

test("normalizeGoalSession restores valid stored sessions and derives duration labels", () => {
  const session = normalizeGoalSession({
    goal: "Ship the focus card",
    durationMinutes: 45,
    startedAt: 1000,
  });

  assert.deepEqual(session, {
    goal: "Ship the focus card",
    durationInput: "45 min",
    durationMinutes: 45,
    startedAt: 1000,
  });
});

test("normalizeGoalSession rejects invalid stored payloads", () => {
  assert.equal(normalizeGoalSession(null), null);
  assert.equal(normalizeGoalSession({ goal: "   " }), null);
});

test("progressForSession returns progress, remaining time, and overtime state", () => {
  const session = {
    goal: "Focus",
    durationInput: "30 min",
    durationMinutes: 30,
    startedAt: 0,
  };

  assert.deepEqual(progressForSession(session, 15 * 60_000), {
    totalMs: 30 * 60_000,
    elapsedMs: 15 * 60_000,
    remainingMs: 15 * 60_000,
    progress: 0.5,
    isOvertime: false,
  });

  assert.deepEqual(progressForSession(session, 31 * 60_000), {
    totalMs: 30 * 60_000,
    elapsedMs: 31 * 60_000,
    remainingMs: -1 * 60_000,
    progress: 1,
    isOvertime: true,
  });

  assert.equal(progressForSession({ ...session, durationMinutes: null }, 1000), null);
});

test("relative labels cover just-started, remaining, and overtime cases", () => {
  assert.equal(formatElapsedLabel(0), "Just started");
  assert.equal(formatElapsedLabel(3 * 60_000), "3 min elapsed");
  assert.equal(formatRemainingLabel(9 * 60_000), "9 min left");
  assert.equal(formatRemainingLabel(0), "Time is up");
  assert.equal(formatRemainingLabel(-2 * 60_000), "Over by 2 min");
});
