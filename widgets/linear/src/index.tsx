import * as React from "react";

import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  Icon,
  Inline,
  openURL,
  RoundedRect,
  ScrollView,
  Section,
  Spacer,
  Stack,
  Text,
  usePreference,
  usePromise,
} from "@skylane/api";

import {
  addUpdatingIssue,
  applyOptimisticState,
  fetchLinearIssueData,
  groupStatesByTeam,
  normalizeIssues,
  normalizePreferenceText,
  normalizeStates,
  parsePositiveInteger,
  removeOptimisticState,
  removeUpdatingIssue,
  updateLinearIssueState,
  useLinearAutoRefresh,
} from "./linear-client.mjs";

function priorityOpacity(index, level) {
  return index < level ? "C7" : "2E";
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

function PriorityBars({ level }) {
  return (
    <Inline spacing={2} alignment="bottom" frame={{ width: 18 }}>
      {[0, 1, 2].map((index) => (
        <RoundedRect
          key={index}
          fill={`#FFFFFF${priorityOpacity(index, level)}`}
          cornerRadius={999}
          width={4}
          height={8 + index * 4}
        />
      ))}
    </Inline>
  );
}

function StatusPill({ status, color }) {
  const stateColor = color || "#FFFFFF6B";

  return (
    <RoundedRect
      fill="#FFFFFF0F"
      strokeColor={withAlpha(stateColor, "2E")}
      strokeWidth={1}
      cornerRadius={8}
      height={24}
    >
      <Inline
        spacing={6}
        alignment="center"
        padding={{ leading: 8, trailing: 8 }}
        frame={{ maxHeight: Infinity }}
      >
        <RoundedRect
          fill={stateColor}
          cornerRadius={999}
          width={6}
          height={6}
        />
        <Text size={10} weight="semibold" color="#FFFFFFC2" lineClamp={1}>
          {status}
        </Text>
        <Icon symbol="chevron.down" size={8} weight="bold" color="#FFFFFF6B" />
      </Inline>
    </RoundedRect>
  );
}

function IssueStatusDropdown({ issue, states, isUpdating, onChange }) {
  return (
    <DropdownMenu
      trigger={
        <StatusPill
          status={isUpdating ? "Updating" : issue.status}
          color={issue.stateColor}
        />
      }
    >
      {states.map((state) => (
        <DropdownMenuCheckboxItem
          key={state.id}
          checked={state.id === issue.stateId}
          onClick={() => {
            if (state.id !== issue.stateId) {
              onChange(issue, state);
            }
          }}
        >
          {state.name}
        </DropdownMenuCheckboxItem>
      ))}
    </DropdownMenu>
  );
}

function IssueRow({ issue, states, isUpdating, onOpen, onStatusChange }) {
  return (
    <RoundedRect
      onPress={() => {
        if (issue.url) {
          onOpen(issue.url);
        }
      }}
      fill="#FFFFFF0D"
      strokeColor="#FFFFFF08"
      strokeWidth={1}
      cornerRadius={12}
      height={40}
      frame={{ maxWidth: Infinity }}
    >
      <Inline
        spacing={6}
        alignment="center"
        padding={{ leading: 10, trailing: 10 }}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <PriorityBars level={issue.priority} />

        <Text
          size={10}
          weight="bold"
          design="monospaced"
          color="#FFFFFF6B"
          lineClamp={1}
          frame={{ width: 44 }}
        >
          {issue.id}
        </Text>

        <Text size={11} weight="medium" color="#FFFFFFD1" lineClamp={1}>
          {issue.title}
        </Text>

        <Spacer />

        <IssueStatusDropdown
          issue={issue}
          states={states}
          isUpdating={isUpdating}
          onChange={onStatusChange}
        />
      </Inline>
    </RoundedRect>
  );
}

function StatePanel({ title, detail }) {
  return (
    <RoundedRect
      fill="#FFFFFF0F"
      strokeColor="#FFFFFF0A"
      strokeWidth={1}
      cornerRadius={12}
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Stack
        spacing={5}
        alignment="center"
        padding={{ leading: 14, trailing: 14 }}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Spacer />
        <Text
          size={12}
          weight="semibold"
          color="#FFFFFFD6"
          alignment="center"
          lineClamp={1}
        >
          {title}
        </Text>
        {detail ? (
          <Text size={10} color="#FFFFFF7A" alignment="center" lineClamp={3}>
            {detail}
          </Text>
        ) : null}
        <Spacer />
      </Stack>
    </RoundedRect>
  );
}

export default function Widget({ environment } = {}) {
  const [apiKey] = usePreference("apiKey");
  const [teamKeyPreference] = usePreference("teamKey");
  const [stateFilterPreference] = usePreference("stateFilter");
  const [maxRowsPreference] = usePreference("maxRows");
  const normalizedApiKey = normalizePreferenceText(apiKey);
  const teamKey = normalizePreferenceText(teamKeyPreference);
  const stateFilter = stateFilterPreference === "all" ? "all" : "active";
  const maxRows = parsePositiveInteger(maxRowsPreference, 8, {
    min: 1,
    max: 20,
  });
  const [stateByIssueId, setStateByIssueId] = React.useState(() => new Map());
  const [updatingIssueIds, setUpdatingIssueIds] = React.useState(
    () => new Set(),
  );
  const [updateError, setUpdateError] = React.useState(null);
  const isVisible = environment?.isVisible === true;
  const assignedIssues = usePromise(
    (signal) => {
      if (!normalizedApiKey) {
        return Promise.resolve({
          needsConfiguration: true,
          issues: [],
          states: [],
        });
      }

      return fetchLinearIssueData({
        apiKey: normalizedApiKey,
        maxRows,
        signal,
      }).then((data) => ({ needsConfiguration: false, ...data }));
    },
    [normalizedApiKey, maxRows],
  );
  useLinearAutoRefresh({
    enabled: Boolean(normalizedApiKey) && isVisible,
    isLoading: assignedIssues.isLoading,
    revalidate: assignedIssues.revalidate,
  });
  const states = React.useMemo(
    () => normalizeStates(assignedIssues.data?.states ?? []),
    [assignedIssues.data?.states],
  );
  const statesByTeam = React.useMemo(() => groupStatesByTeam(states), [states]);
  const issues = React.useMemo(
    () =>
      normalizeIssues(assignedIssues.data?.issues ?? [], {
        teamKey,
        stateFilter,
        maxRows,
        stateByIssueId,
      }),
    [
      assignedIssues.data?.issues,
      maxRows,
      stateByIssueId,
      stateFilter,
      teamKey,
    ],
  );

  function handleOpenIssue(url) {
    openURL(url);
  }

  async function handleStatusChange(issue, state) {
    if (!normalizedApiKey || updatingIssueIds.has(issue.issueId)) {
      return;
    }

    setUpdateError(null);
    setStateByIssueId((current) =>
      applyOptimisticState(current, issue.issueId, state),
    );
    setUpdatingIssueIds((current) => addUpdatingIssue(current, issue.issueId));

    try {
      await updateLinearIssueState({
        apiKey: normalizedApiKey,
        issueId: issue.issueId,
        stateId: state.id,
      });
      assignedIssues.revalidate();
    } catch (error) {
      setUpdateError(error);
      setStateByIssueId((current) =>
        removeOptimisticState(current, issue.issueId),
      );
    } finally {
      setUpdatingIssueIds((current) =>
        removeUpdatingIssue(current, issue.issueId),
      );
    }
  }

  let body = null;
  if (assignedIssues.isLoading && !assignedIssues.data) {
    body = <StatePanel title="Loading Linear" />;
  } else if (assignedIssues.error) {
    body = (
      <StatePanel
        title="Unable to load Linear"
        detail={assignedIssues.error.message}
      />
    );
  } else if (assignedIssues.data?.needsConfiguration) {
    body = (
      <StatePanel
        title="Connect Linear"
        detail="Add a personal API key in widget settings."
      />
    );
  } else if (issues.length === 0) {
    body = <StatePanel title="No matching issues" />;
  } else if (updateError) {
    body = (
      <StatePanel
        title="Unable to update Linear"
        detail={updateError.message}
      />
    );
  } else {
    body = (
      <ScrollView
        fadeEdges="bottom"
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Stack
          spacing={8}
          padding={{ bottom: 28 }}
          frame={{ maxWidth: Infinity }}
        >
          {issues.map((issue) => (
            <IssueRow
              key={issue.issueId}
              issue={issue}
              states={statesByTeam.get(issue.teamId) ?? []}
              isUpdating={updatingIssueIds.has(issue.issueId)}
              onOpen={handleOpenIssue}
              onStatusChange={handleStatusChange}
            />
          ))}
        </Stack>
      </ScrollView>
    );
  }

  return (
    <Section spacing="sm" frame={{ maxWidth: Infinity, maxHeight: Infinity }}>
      {body}
    </Section>
  );
}
