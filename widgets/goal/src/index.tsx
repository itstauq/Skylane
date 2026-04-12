import { useEffect, useMemo, useState } from "react";

import {
  Button,
  IconButton,
  Inline,
  Input,
  ProgressBar,
  RoundedRect,
  Section,
  Spacer,
  Stack,
  Text,
  useLocalStorage,
  useTheme,
} from "@skylane/api";

import {
  createGoalSession,
  formatDurationCompact,
  formatDurationLabel,
  formatElapsedLabel,
  formatRemainingLabel,
  normalizeGoalDraft,
  normalizeGoalSession,
  parseDurationMinutes,
  progressForSession,
} from "./goal-state.mjs";

const STORAGE_KEY = "active-goal-session";
const DURATION_STEP = 15;
const MIN_DURATION = 15;
const MAX_DURATION = 120;

const PLACEHOLDER_GOALS = [
  "Finish the kickoff email",
  "Land the PR before standup",
  "Close out today's design notes",
  "Wrap the draft and send it",
  "Ship the changelog update",
  "Clear the review queue",
  "Outline the launch plan",
];

function pickPlaceholderGoal() {
  const index = Math.floor(Math.random() * PLACEHOLDER_GOALS.length);
  return PLACEHOLDER_GOALS[index];
}

function withAlpha(color, alpha) {
  if (typeof color !== "string") {
    return color;
  }

  const normalized = color.startsWith("#") ? color.slice(1) : color;
  if (normalized.length < 6) {
    return color;
  }

  return `#${normalized.slice(0, 6)}${alpha}`;
}

function getLayoutMetrics(span) {
  if (span >= 6) {
    return {
      paddingX: 0,
      paddingY: 8,
      spacing: 14,
      promptSize: 17,
      heroSize: 30,
      progressHeight: 10,
      actionWidth: 104,
      iconButtonSize: 28,
      compactActions: false,
    };
  }

  if (span >= 4) {
    return {
      paddingX: 0,
      paddingY: 8,
      spacing: 12,
      promptSize: 16,
      heroSize: 26,
      progressHeight: 9,
      actionWidth: 98,
      iconButtonSize: 26,
      compactActions: false,
    };
  }

  return {
    paddingX: 0,
    paddingY: 8,
    spacing: 10,
    promptSize: 15,
    heroSize: 24,
    progressHeight: 8,
    actionWidth: 96,
    iconButtonSize: 24,
    compactActions: true,
  };
}

function durationInputForMinutes(minutes) {
  return minutes == null ? "" : `${minutes} min`;
}

function clampDuration(minutes) {
  if (!Number.isFinite(minutes)) {
    return MIN_DURATION;
  }

  return Math.max(MIN_DURATION, Math.min(MAX_DURATION, minutes));
}

function GoalProgressBar({
  progress,
  height,
  activeFill,
  trackFill,
  warningColor,
  mutedTextColor,
}) {
  const tintColor = progress.isOvertime ? warningColor : activeFill;

  return (
    <Stack spacing={8} alignment="center" frame={{ maxWidth: Infinity }}>
      <ProgressBar
        value={progress.progress}
        height={height}
        tint={tintColor}
        track={trackFill}
      />

      <Inline alignment="center" spacing={8} frame={{ maxWidth: Infinity }}>
        <Text size={11} weight="semibold" color={mutedTextColor}>
          {formatElapsedLabel(progress.elapsedMs)}
        </Text>
        <Spacer />
        <Text
          size={11}
          alignment="trailing"
          weight="semibold"
          color={progress.isOvertime ? warningColor : mutedTextColor}
        >
          {formatRemainingLabel(progress.remainingMs)}
        </Text>
      </Inline>
    </Stack>
  );
}

function DurationStepper({ minutes, mutedTextColor, onDecrease, onIncrease }) {
  const durationText = Number.isFinite(minutes)
    ? formatDurationCompact(minutes)
    : "30m";

  return (
    <RoundedRect
      fill={withAlpha(mutedTextColor, "12")}
      strokeColor={withAlpha(mutedTextColor, "16")}
      cornerRadius={999}
      height={40}
      frame={{ maxWidth: Infinity }}
    >
      <Inline
        alignment="center"
        spacing={4}
        padding={{ leading: 6, trailing: 6 }}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <IconButton
          symbol="minus"
          variant="ghost"
          width={28}
          height={28}
          iconSize={11}
          onClick={onDecrease}
        />
        <Text
          size={12}
          weight="bold"
          color={mutedTextColor}
          alignment="center"
          lineClamp={1}
          minimumScaleFactor={0.8}
          frame={{ maxWidth: Infinity }}
        >
          {durationText}
        </Text>
        <IconButton
          symbol="plus"
          variant="ghost"
          width={28}
          height={28}
          iconSize={11}
          onClick={onIncrease}
        />
      </Inline>
    </RoundedRect>
  );
}

function GoalComposer({
  goalDraft,
  selectedDurationMinutes,
  canSubmit,
  metrics,
  questionColor,
  mutedTextColor,
  onGoalChange,
  onDecreaseDuration,
  onIncreaseDuration,
  onSubmit,
}) {
  const durationLabel = Number.isFinite(selectedDurationMinutes)
    ? formatDurationLabel(selectedDurationMinutes)
    : "30 min";
  const [placeholderText] = useState(() => `Try "${pickPlaceholderGoal()}"...`);

  return (
    <Stack
      spacing={metrics.spacing}
      padding={{
        leading: metrics.paddingX,
        trailing: metrics.paddingX,
        top: metrics.paddingY,
        bottom: metrics.paddingY,
      }}
      alignment="leading"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Text
        size={metrics.promptSize}
        weight="semibold"
        color={questionColor}
        alignment="center"
        lineClamp={1}
        minimumScaleFactor={0.6}
        frame={{ maxWidth: Infinity }}
      >
        {`What is your next ${durationLabel} goal?`}
      </Text>

      <Input
        value={goalDraft}
        placeholder={placeholderText}
        onValueChange={(value) => onGoalChange(normalizeGoalDraft(value))}
        onSubmitValue={canSubmit ? onSubmit : undefined}
      />

      <Spacer />

      <Inline
        alignment="center"
        spacing={metrics.spacing}
        frame={{ maxWidth: Infinity }}
      >
        <DurationStepper
          minutes={selectedDurationMinutes}
          mutedTextColor={mutedTextColor}
          onDecrease={onDecreaseDuration}
          onIncrease={onIncreaseDuration}
        />
        <Button
          title="Start"
          variant="default"
          shape="pill"
          width={metrics.actionWidth}
          height={40}
          cornerRadius={20}
          onClick={canSubmit ? onSubmit : undefined}
        />
      </Inline>
    </Stack>
  );
}

function ActiveGoalCard({
  session,
  progress,
  metrics,
  heroTextColor,
  mutedTextColor,
  accentFill,
  warningColor,
  onDone,
}) {
  return (
    <Stack
      spacing={metrics.spacing}
      padding={{
        leading: metrics.paddingX,
        trailing: metrics.paddingX,
        top: metrics.paddingY,
        bottom: metrics.paddingY,
      }}
      alignment="center"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Text
        size={metrics.heroSize}
        weight="bold"
        color={heroTextColor}
        alignment="center"
        lineClamp={3}
        minimumScaleFactor={0.8}
      >
        {session.goal}
      </Text>

      <GoalProgressBar
        progress={progress}
        height={metrics.progressHeight}
        activeFill={accentFill}
        trackFill={withAlpha(heroTextColor, "12")}
        warningColor={warningColor}
        mutedTextColor={mutedTextColor}
      />

      <Spacer />

      <Button title="Done" variant="secondary" shape="pill" onClick={onDone} />
    </Stack>
  );
}

export default function Widget({ environment }) {
  const theme = useTheme();
  const metrics = getLayoutMetrics(environment?.span ?? 4);
  const [storedSession, setStoredSession] = useLocalStorage(STORAGE_KEY, null);
  const session = useMemo(
    () => normalizeGoalSession(storedSession),
    [storedSession],
  );
  const [goalDraft, setGoalDraft] = useState("");
  const [durationDraft, setDurationDraft] = useState(() =>
    durationInputForMinutes(30),
  );
  const [nowMs, setNowMs] = useState(() => Date.now());

  const selectedDurationMinutes = parseDurationMinutes(durationDraft);
  const progress = progressForSession(session, nowMs);
  const canSubmit = goalDraft.trim().length > 0;

  const questionColor = withAlpha(theme.colors.foreground, "F4");
  const heroTextColor = withAlpha(theme.colors.foreground, "F7");
  const mutedTextColor = withAlpha(theme.colors.foreground, "9A");

  useEffect(() => {
    if (!session) {
      return undefined;
    }

    const timerID = setInterval(() => {
      setNowMs(Date.now());
    }, 1000);

    return () => clearInterval(timerID);
  }, [session]);

  function handleDecreaseDuration() {
    setDurationDraft((current) => {
      const currentMinutes = parseDurationMinutes(current);
      const nextMinutes =
        currentMinutes == null
          ? 30
          : clampDuration(currentMinutes - DURATION_STEP);
      return durationInputForMinutes(nextMinutes);
    });
  }

  function handleIncreaseDuration() {
    setDurationDraft((current) => {
      const currentMinutes = parseDurationMinutes(current);
      const nextMinutes =
        currentMinutes == null
          ? 30
          : clampDuration(currentMinutes + DURATION_STEP);
      return durationInputForMinutes(nextMinutes);
    });
  }

  function handleSubmit() {
    const nextSession = createGoalSession({
      goal: goalDraft,
      durationInput: durationDraft,
      now: Date.now(),
    });

    if (!nextSession) {
      setGoalDraft(normalizeGoalDraft(goalDraft).trimStart());
      return;
    }

    setStoredSession(nextSession);
    setGoalDraft(nextSession.goal);
    setDurationDraft(nextSession.durationInput);
    setNowMs(nextSession.startedAt);
  }

  function handleDone() {
    setStoredSession(null);
    setGoalDraft("");
    setDurationDraft(durationInputForMinutes(30));
    setNowMs(Date.now());
  }

  const showActiveCard = session != null && progress != null;

  return (
    <Section frame={{ maxWidth: Infinity, maxHeight: Infinity }}>
      {showActiveCard ? (
        <ActiveGoalCard
          session={session}
          progress={progress}
          metrics={metrics}
          heroTextColor={heroTextColor}
          mutedTextColor={mutedTextColor}
          accentFill={theme.colors.primary}
          warningColor={theme.colors.warning}
          onDone={handleDone}
        />
      ) : (
        <GoalComposer
          goalDraft={goalDraft}
          selectedDurationMinutes={selectedDurationMinutes}
          canSubmit={canSubmit}
          metrics={metrics}
          questionColor={questionColor}
          mutedTextColor={mutedTextColor}
          onGoalChange={setGoalDraft}
          onDecreaseDuration={handleDecreaseDuration}
          onIncreaseDuration={handleIncreaseDuration}
          onSubmit={handleSubmit}
        />
      )}
    </Section>
  );
}
