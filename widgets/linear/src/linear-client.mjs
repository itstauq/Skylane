import * as React from "react";

const LINEAR_API_URL = "https://api.linear.app/graphql";
const ACTIVE_STATE_TYPES = new Set([
  "triage",
  "backlog",
  "unstarted",
  "started",
]);

export function useLinearAutoRefresh({
  enabled,
  intervalMs = 10000,
  isLoading,
  revalidate,
}) {
  const isLoadingRef = React.useRef(isLoading);

  React.useEffect(() => {
    isLoadingRef.current = isLoading;
  }, [isLoading]);

  React.useEffect(() => {
    if (!enabled) {
      return undefined;
    }

    let timeoutId = null;
    let isCancelled = false;

    function refreshAndScheduleNext() {
      if (isCancelled) {
        return;
      }

      if (!isLoadingRef.current) {
        revalidate();
      }

      timeoutId = setTimeout(refreshAndScheduleNext, intervalMs);
    }

    refreshAndScheduleNext();

    return () => {
      isCancelled = true;
      if (timeoutId !== null) {
        clearTimeout(timeoutId);
      }
    };
  }, [enabled, intervalMs, revalidate]);
}

const ASSIGNED_ISSUES_QUERY = `
  query SkylaneAssignedIssues($first: Int!) {
    viewer {
      assignedIssues(first: $first) {
        nodes {
          id
          identifier
          title
          priority
          url
          updatedAt
          state {
            id
            name
            type
            color
          }
          team {
            id
            key
          }
        }
      }
    }
    workflowStates(first: 100) {
      nodes {
        id
        name
        type
        color
        team {
          id
          key
        }
      }
    }
  }
`;

const UPDATE_ISSUE_STATE_MUTATION = `
  mutation SkylaneUpdateIssueState($id: String!, $stateId: String!) {
    issueUpdate(id: $id, input: { stateId: $stateId }) {
      success
      issue {
        id
        state {
          id
          name
          type
          color
        }
      }
    }
  }
`;

export function normalizePreferenceText(value) {
  return typeof value === "string" ? value.trim() : "";
}

export function parsePositiveInteger(value, fallback, { min = 1, max = 50 } = {}) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }

  return Math.max(min, Math.min(max, parsed));
}

export async function fetchLinearIssueData({ apiKey, maxRows, signal }) {
  const data = await linearGraphQL({
    apiKey,
    query: ASSIGNED_ISSUES_QUERY,
    variables: {
      first: Math.min(Math.max(maxRows * 3, maxRows), 50),
    },
    signal,
  });

  return {
    issues: data?.viewer?.assignedIssues?.nodes ?? [],
    states: data?.workflowStates?.nodes ?? [],
  };
}

export async function updateLinearIssueState({ apiKey, issueId, stateId }) {
  const data = await linearGraphQL({
    apiKey,
    query: UPDATE_ISSUE_STATE_MUTATION,
    variables: {
      id: issueId,
      stateId,
    },
  });

  if (!data?.issueUpdate?.success) {
    throw new Error("Linear did not update the issue state.");
  }

  return data.issueUpdate.issue;
}

export function normalizeStates(states) {
  return states
    .filter((state) => state?.id && state?.name && state?.team?.id)
    .map((state) => ({
      id: state.id,
      name: state.name,
      type: state.type,
      color: state.color,
      teamId: state.team.id,
      teamKey: state.team.key,
    }));
}

export function groupStatesByTeam(states) {
  return states.reduce((groups, state) => {
    const existing = groups.get(state.teamId) ?? [];
    existing.push(state);
    groups.set(state.teamId, existing);
    return groups;
  }, new Map());
}

export function normalizeIssues(
  issues,
  { teamKey, stateFilter, maxRows, stateByIssueId },
) {
  const normalizedTeamKey = teamKey.toUpperCase();

  return issues
    .filter((issue) => matchesFilters(issue, normalizedTeamKey, stateFilter))
    .sort(compareUpdatedAtDesc)
    .slice(0, maxRows)
    .map((issue) => normalizeIssue(issue, stateByIssueId));
}

export function applyOptimisticState(current, issueId, state) {
  const next = new Map(current);
  next.set(issueId, state);
  return next;
}

export function removeOptimisticState(current, issueId) {
  const next = new Map(current);
  next.delete(issueId);
  return next;
}

export function addUpdatingIssue(current, issueId) {
  const next = new Set(current);
  next.add(issueId);
  return next;
}

export function removeUpdatingIssue(current, issueId) {
  const next = new Set(current);
  next.delete(issueId);
  return next;
}

async function linearGraphQL({ apiKey, query, variables, signal }) {
  const response = await fetch(LINEAR_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: apiKey,
    },
    body: JSON.stringify({
      query,
      variables,
    }),
    signal,
  });

  if (!response.ok) {
    throw new Error(`Linear request failed with status ${response.status}`);
  }

  const payload = await response.json();
  if (Array.isArray(payload?.errors) && payload.errors.length > 0) {
    throw new Error(payload.errors[0]?.message || "Linear returned an error.");
  }

  return payload?.data;
}

function matchesFilters(issue, normalizedTeamKey, stateFilter) {
  if (normalizedTeamKey && issue?.team?.key !== normalizedTeamKey) {
    return false;
  }

  const stateType = issue?.state?.type;
  return stateFilter !== "active" || ACTIVE_STATE_TYPES.has(stateType);
}

function compareUpdatedAtDesc(a, b) {
  return (
    new Date(b.updatedAt ?? 0).getTime() -
    new Date(a.updatedAt ?? 0).getTime()
  );
}

function normalizeIssue(issue, stateByIssueId) {
  const overrideState = stateByIssueId.get(issue.id);
  const state = overrideState ?? issue.state;

  return {
    id: issue.identifier || issue.id,
    issueId: issue.id,
    title: issue.title || "Untitled issue",
    status: state?.name || "No status",
    stateId: state?.id,
    stateColor: state?.color,
    teamId: issue.team?.id,
    teamKey: issue.team?.key,
    priority: displayLevelForLinearPriority(issue.priority),
    url: issue.url,
  };
}

function displayLevelForLinearPriority(priority) {
  switch (priority) {
    case 1:
    case 2:
      return 3;
    case 3:
      return 2;
    case 4:
      return 1;
    default:
      return 0;
  }
}
