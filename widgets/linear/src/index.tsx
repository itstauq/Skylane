import { useMemo } from "react";

import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  Icon,
  Inline,
  RoundedRect,
  ScrollView,
  Section,
  Spacer,
  Stack,
  Text,
  useLocalStorage,
} from "@skylane/api";

const STATUS_OPTIONS = ["To Do", "In Progress", "Done"];
const STATUS_STORAGE_KEY = "linear-issue-statuses";

const ISSUES = [
  {
    id: "LIN-142",
    title: "Refine widget host row",
    status: "In Progress",
    priority: 3,
  },
  {
    id: "LIN-151",
    title: "Add edit mode affordances",
    status: "To Do",
    priority: 2,
  },
  {
    id: "LIN-159",
    title: "Ship preview gallery",
    status: "Done",
    priority: 1,
  },
  {
    id: "LIN-164",
    title: "Fix tab-strip overflow edge case",
    status: "To Do",
    priority: 2,
  },
  {
    id: "LIN-171",
    title: "Polish capture empty state",
    status: "In Progress",
    priority: 3,
  },
  {
    id: "LIN-176",
    title: "Audit widget height constraints",
    status: "Done",
    priority: 1,
  },
];

function priorityOpacity(index, level) {
  return index < level ? "C7" : "2E";
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

function StatusPill({ status }) {
  return (
    <RoundedRect fill="#FFFFFF0F" cornerRadius={8} height={24}>
      <Inline
        spacing={6}
        alignment="center"
        padding={{ leading: 8, trailing: 8 }}
        frame={{ maxHeight: Infinity }}
      >
        <Text size={10} weight="semibold" color="#FFFFFFC2" lineClamp={1}>
          {status}
        </Text>
        <Icon symbol="chevron.down" size={8} weight="bold" color="#FFFFFF6B" />
      </Inline>
    </RoundedRect>
  );
}

function IssueStatusDropdown({ status, onChange }) {
  return (
    <DropdownMenu trigger={<StatusPill status={status} />}>
      {STATUS_OPTIONS.map((option) => (
        <DropdownMenuCheckboxItem
          key={option}
          checked={option === status}
          onClick={() => onChange(option)}
        >
          {option}
        </DropdownMenuCheckboxItem>
      ))}
    </DropdownMenu>
  );
}

function IssueRow({ issue, onStatusChange }) {
  return (
    <RoundedRect
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
          status={issue.status}
          onChange={(status) => onStatusChange(issue.id, status)}
        />
      </Inline>
    </RoundedRect>
  );
}

export default function Widget() {
  const [statusByIssueID, setStatusByIssueID] = useLocalStorage(
    STATUS_STORAGE_KEY,
    {}
  );
  const issues = useMemo(
    () => (
      ISSUES.map((issue) => ({
        ...issue,
        status: STATUS_OPTIONS.includes(statusByIssueID?.[issue.id])
          ? statusByIssueID[issue.id]
          : issue.status,
      }))
    ),
    [statusByIssueID]
  );

  function handleStatusChange(issueID, status) {
    setStatusByIssueID((current) => ({
      ...(current && typeof current === "object" ? current : {}),
      [issueID]: status,
    }));
  }

  return (
    <Section spacing="sm" frame={{ maxWidth: Infinity, maxHeight: Infinity }}>
      <ScrollView
        fadeEdges="bottom"
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Stack spacing={8} padding={{ bottom: 28 }} frame={{ maxWidth: Infinity }}>
          {issues.map((issue) => (
            <IssueRow
              key={issue.id}
              issue={issue}
              onStatusChange={handleStatusChange}
            />
          ))}
        </Stack>
      </ScrollView>
    </Section>
  );
}
