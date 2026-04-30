import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import {
  cancelNotification,
  scheduleNotification,
  useLocalStorage,
  usePreference,
} from "@skylane/api";

import {
  advanceCompletedSession,
  SESSION_COMPLETE_NOTIFICATION_ID,
  STORAGE_KEY,
  createDefaultState,
  createPomodoroViewModel,
  normalizePreferences,
  normalizeState,
  notificationPayloadForSession,
  pauseSession,
  resetCycle,
  startOrResumeSession,
  syncElapsedSession,
} from "./pomodoro-state.mjs";

/**
 * @typedef {ReturnType<typeof createPomodoroViewModel> & {
 *   preferences: ReturnType<typeof normalizePreferences>
 *   handlePrimaryPress: () => void
 *   handleResetCycle: () => void
 *   handleSkipStep: () => void
 * }} PomodoroController
 */

function runAsync(task, message) {
  void task.catch((error) => {
    console.warn(message, error);
  });
}

function usePomodoroPreferences() {
  const [focusMinutes] = usePreference("focusMinutes");
  const [shortBreakMinutes] = usePreference("shortBreakMinutes");
  const [longBreakMinutes] = usePreference("longBreakMinutes");
  const [rounds] = usePreference("rounds");

  return useMemo(
    () =>
      normalizePreferences({
        focusMinutes,
        shortBreakMinutes,
        longBreakMinutes,
        rounds,
      }),
    [focusMinutes, longBreakMinutes, rounds, shortBreakMinutes]
  );
}

function usePersistentPomodoroState() {
  const [storedState, setStoredState] = useLocalStorage(
    STORAGE_KEY,
    createDefaultState()
  );
  const state = useMemo(() => normalizeState(storedState), [storedState]);

  const updateState = useCallback((transform) => {
    setStoredState((currentState) => transform(normalizeState(currentState)));
  }, [setStoredState]);

  return {
    state,
    updateState,
  };
}

function useRunningClock(endsAtMs) {
  const [nowMs, setNowMs] = useState(() => Date.now());

  useEffect(() => {
    if (endsAtMs == null) {
      return undefined;
    }

    let timeoutID;

    function scheduleTick() {
      const current = Date.now();
      setNowMs(current);

      const remainingMs = endsAtMs - current;
      if (remainingMs <= 0) {
        return;
      }

      const nextDelay = remainingMs % 1000 || 1000;
      timeoutID = setTimeout(scheduleTick, nextDelay);
    }

    scheduleTick();

    return () => {
      clearTimeout(timeoutID);
    };
  }, [endsAtMs]);

  return nowMs;
}

function usePomodoroNotificationSync(state) {
  const scheduledEndsAtRef = useRef(null);

  useEffect(() => {
    if (state.status === "running" && state.endsAtMs != null) {
      if (state.endsAtMs <= Date.now()) {
        scheduledEndsAtRef.current = null;
        return;
      }

      scheduledEndsAtRef.current = state.endsAtMs;
      runAsync(
        scheduleNotification(
          SESSION_COMPLETE_NOTIFICATION_ID,
          notificationPayloadForSession(state.sessionKind, state.endsAtMs)
        ),
        "Failed to schedule Pomodoro notification"
      );
      return;
    }

    const scheduledEndsAtMs = scheduledEndsAtRef.current;
    scheduledEndsAtRef.current = null;
    if (scheduledEndsAtMs != null && Date.now() < scheduledEndsAtMs) {
      runAsync(
        cancelNotification(SESSION_COMPLETE_NOTIFICATION_ID),
        "Failed to cancel Pomodoro notification"
      );
    }

    // A running timer should keep its pending notification if the widget unmounts.
  }, [state.endsAtMs, state.sessionKind, state.status]);
}

function useElapsedSessionSync(state, preferences, nowMs, updateState) {
  useEffect(() => {
    if (state.status !== "running" || state.endsAtMs == null || nowMs < state.endsAtMs) {
      return;
    }

    updateState((currentState) => syncElapsedSession(currentState, preferences, Date.now()));
  }, [
    nowMs,
    preferences.focusMinutes,
    preferences.longBreakMinutes,
    preferences.rounds,
    preferences.shortBreakMinutes,
    state.endsAtMs,
    state.status,
    updateState,
  ]);
}

/** @returns {PomodoroController} */
export function usePomodoroController() {
  const preferences = usePomodoroPreferences();
  const { state, updateState } = usePersistentPomodoroState();
  const nowMs = useRunningClock(state.status === "running" ? state.endsAtMs : null);
  const viewModel = useMemo(
    () => createPomodoroViewModel(state, preferences, nowMs),
    [nowMs, preferences, state]
  );

  useElapsedSessionSync(state, preferences, nowMs, updateState);
  usePomodoroNotificationSync(state);

  const handlePrimaryPress = useCallback(() => {
    const now = Date.now();

    updateState((currentState) => {
      if (currentState.status === "running") {
        return pauseSession(currentState, preferences, now);
      }

      return startOrResumeSession(currentState, preferences, now);
    });
  }, [preferences, updateState]);

  const handleResetCycle = useCallback(() => {
    updateState(() => resetCycle());
  }, [updateState]);

  const handleSkipStep = useCallback(() => {
    updateState((currentState) => advanceCompletedSession(currentState, preferences));
  }, [preferences, updateState]);

  return {
    preferences,
    ...viewModel,
    handlePrimaryPress,
    handleResetCycle,
    handleSkipStep,
  };
}
