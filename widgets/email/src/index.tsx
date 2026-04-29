import * as React from "react";

import {
  Button,
  Card,
  CardContent,
  CardDescription,
  CardTitle,
  Circle,
  connectTCP,
  IconButton,
  Inline,
  Overlay,
  RoundedRect,
  ScrollView,
  Section,
  Spacer,
  Stack,
  Text,
  usePreference,
  usePromise,
  useTheme,
} from "@skylane/api";

import {
  fetchIMAPMessageDetail,
  fetchUnreadIMAPMessages,
  markIMAPMessageRead,
  watchIMAPMailbox,
} from "./imap-client.mjs";
import {
  getInboxViewState,
  isAbortError,
  normalizeEmailMessages,
  normalizePreferenceText,
  sleep,
  withAlpha,
} from "./utils.mjs";

function Header({ count, colors, onRefresh }) {
  return (
    <Inline spacing={8} alignment="center" frame={{ maxWidth: Infinity }}>
      <Text size={11} weight="semibold" color="#FFFFFFD1" lineClamp={1}>
        {count} unread
      </Text>

      <Spacer />

      <IconButton
        symbol="arrow.clockwise"
        variant="ghost"
        size="small"
        iconSize={11}
        width={24}
        height={24}
        color={colors.mutedForeground}
        onClick={onRefresh}
      />
    </Inline>
  );
}

function MailRow({ message, onOpen }) {
  return (
    <Stack onPress={() => onOpen(message)} frame={{ maxWidth: Infinity }}>
      <RoundedRect
        fill="#FFFFFF0F"
        strokeColor="#FFFFFF0A"
        strokeWidth={1}
        cornerRadius={12}
        height={44}
        frame={{ maxWidth: Infinity }}
      >
        <Inline
          spacing={10}
          alignment="center"
          padding={{ leading: 10, trailing: 10 }}
          frame={{ maxWidth: Infinity, maxHeight: Infinity }}
        >
          <Circle fill={withAlpha(message.tint, "2E")} width={28} height={28}>
            <Text
              size={11}
              weight="bold"
              color={message.tint}
              alignment="center"
            >
              {message.avatar}
            </Text>
          </Circle>

          <Stack spacing={3} alignment="leading" frame={{ maxWidth: Infinity }}>
            <Inline
              spacing={6}
              alignment="center"
              frame={{ maxWidth: Infinity }}
            >
              <Text size={10} weight="semibold" color="#FFFFFFDB" lineClamp={1}>
                {message.sender}
              </Text>
              <Spacer />
              {message.unread && (
                <Circle fill="#FA6478EB" width={6} height={6} />
              )}
            </Inline>

            <Text size={11} weight="medium" color="#FFFFFF8A" lineClamp={1}>
              {message.subject}
            </Text>
          </Stack>
        </Inline>
      </RoundedRect>
    </Stack>
  );
}

function SetupPrompt() {
  return (
    <RoundedRect
      fill="#FFFFFF0F"
      strokeColor="#FFFFFF0A"
      strokeWidth={1}
      cornerRadius={12}
      height={58}
      frame={{ maxWidth: Infinity }}
    >
      <Stack
        spacing={4}
        alignment="leading"
        padding={{ leading: 12, trailing: 12 }}
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Spacer />
        <Text size={11} weight="semibold" color="#FFFFFFD6" lineClamp={1}>
          Configure mailbox
        </Text>
        <Text size={10} color="#FFFFFF7A" lineClamp={2}>
          Add IMAP credentials in widget settings.
        </Text>
        <Spacer />
      </Stack>
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
        spacing={0}
        alignment="center"
        frame={{ maxWidth: Infinity, maxHeight: Infinity }}
      >
        <Spacer />
        <Text
          size={11}
          weight="semibold"
          color="#FFFFFFD6"
          alignment="center"
          lineClamp={1}
        >
          {title}
        </Text>
        {detail && (
          <Text size={10} color="#FFFFFF7A" alignment="center" lineClamp={3}>
            {detail}
          </Text>
        )}
        <Spacer />
      </Stack>
    </RoundedRect>
  );
}

function ScrollableBody({ children }) {
  return (
    <ScrollView
      fadeEdges="bottom"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Stack
        spacing={8}
        alignment="leading"
        padding={{ bottom: 18 }}
        frame={{ maxWidth: Infinity }}
      >
        {children}
      </Stack>
    </ScrollView>
  );
}

function MessageList({ messages, onOpenMessage }) {
  return (
    <ScrollableBody>
      {messages.map((message) => (
        <MailRow key={message.id} message={message} onOpen={onOpenMessage} />
      ))}
    </ScrollableBody>
  );
}

function InboxBody({ state, onOpenMessage }) {
  switch (state.type) {
    case "panel":
      return <StatePanel title={state.title} detail={state.detail} />;
    case "setup":
      return (
        <ScrollableBody>
          <SetupPrompt />
        </ScrollableBody>
      );
    case "messages":
      return (
        <MessageList messages={state.messages} onOpenMessage={onOpenMessage} />
      );
    default:
      return null;
  }
}

function MessageDetailsDialog({
  message,
  detail,
  isMarkingRead,
  markReadError,
  colors,
  onClose,
  onMarkRead,
}) {
  const body = detail.isLoading
    ? "Loading message..."
    : detail.error
      ? detail.error.message
      : detail.data?.body || "No preview available.";

  return (
    <Overlay placement="center">
      <Card
        variant="accent"
        cornerRadius={18}
        fill={colors.card}
        strokeColor={withAlpha(colors.primary, "33")}
        frame={{ maxWidth: 228 }}
      >
        <ScrollView
          fadeEdges="both"
          frame={{ maxWidth: Infinity, maxHeight: 220 }}
        >
          <CardContent
            spacing={10}
            alignment="leading"
            padding={{ top: 14, leading: 14, trailing: 14, bottom: 14 }}
          >
            <Stack
              spacing={5}
              alignment="leading"
              frame={{ maxWidth: Infinity }}
            >
              <CardTitle lineClamp={2} frame={{ maxWidth: 176 }}>
                {message.subject}
              </CardTitle>
              <CardDescription color="#FFFFFF8A">
                {message.sender}
              </CardDescription>
            </Stack>

            <Text size={11} color="#FFFFFFD6">
              {body}
            </Text>

            {markReadError ? (
              <Text size={10} color="#FA757A" lineClamp={2}>
                {markReadError.message}
              </Text>
            ) : null}

            <Stack spacing={6} alignment="center" frame={{ maxWidth: Infinity }}>
              <Button
                title={isMarkingRead ? "Marking..." : "Mark as read"}
                variant="secondary"
                width={112}
                onClick={onMarkRead}
              />
              <Button
                title="Close"
                variant="ghost"
                width={58}
                onClick={onClose}
              />
            </Stack>
          </CardContent>
        </ScrollView>
        <Overlay placement="top-end" inset="sm">
          <IconButton
            symbol="xmark"
            variant="subtle"
            size="small"
            iconSize={9}
            width={22}
            height={22}
            color="#FFFFFFA6"
            onClick={onClose}
          />
        </Overlay>
      </Card>
    </Overlay>
  );
}

export default function Widget() {
  const theme = useTheme();
  const [selectedMessage, setSelectedMessage] = React.useState(null);
  const [readMessageUIDs, setReadMessageUIDs] = React.useState(() => new Set());
  const [isMarkingRead, setIsMarkingRead] = React.useState(false);
  const [markReadError, setMarkReadError] = React.useState(null);
  const [email] = usePreference("email");
  const [password] = usePreference("password");
  const [host] = usePreference("host");
  const [port] = usePreference("port");
  const [mailbox] = usePreference("mailbox");
  const [maxRows] = usePreference("maxRows");
  const inbox = usePromise(
    (signal) =>
      fetchUnreadIMAPMessages({
        email,
        password,
        host,
        port,
        mailbox,
        maxRows,
        connect: connectTCP,
        signal,
      }),
    [email, password, host, port, mailbox, maxRows],
  );
  const inboxMessages = inbox.data?.messages ?? [];
  const readVisibleCount = inboxMessages.filter((message) => {
    return typeof message?.uid === "string" && readMessageUIDs.has(message.uid);
  }).length;
  const messages = React.useMemo(
    () =>
      normalizeEmailMessages(inboxMessages).filter(
        (message) => !message.uid || !readMessageUIDs.has(message.uid),
      ),
    [inboxMessages, readMessageUIDs],
  );
  const unreadCount = Math.max(
    0,
    (inbox.data?.unreadCount ?? 0) - readVisibleCount,
  );
  const viewState = getInboxViewState(inbox, messages);
  const selectedUID = selectedMessage?.uid;
  const messageDetail = usePromise(
    (signal) =>
      fetchIMAPMessageDetail({
        email,
        password,
        host,
        port,
        mailbox,
        uid: selectedUID,
        connect: connectTCP,
        signal,
      }),
    [email, password, host, port, mailbox, selectedUID],
  );
  React.useEffect(() => {
    const hasConfiguration = Boolean(
      normalizePreferenceText(email)
      && normalizePreferenceText(password)
      && normalizePreferenceText(host),
    );
    if (!hasConfiguration || inbox.isLoading || inbox.error || inbox.data?.needsConfiguration) {
      return undefined;
    }

    const controller = new AbortController();
    let retryDelay = 5000;

    async function runWatcher() {
      while (!controller.signal.aborted) {
        try {
          await watchIMAPMailbox({
            email,
            password,
            host,
            port,
            mailbox,
            connect: connectTCP,
            signal: controller.signal,
            onReady() {
              retryDelay = 5000;
            },
            onChange() {
              inbox.revalidate();
            },
          });
        } catch (error) {
          if (controller.signal.aborted || isAbortError(error)) {
            return;
          }

          try {
            await sleep(retryDelay, controller.signal);
          } catch (sleepError) {
            if (isAbortError(sleepError)) {
              return;
            }

            throw sleepError;
          }
          retryDelay = Math.min(retryDelay * 2, 60000);
        }
      }
    }

    runWatcher();
    return () => {
      controller.abort();
    };
  }, [
    email,
    password,
    host,
    port,
    mailbox,
    inbox.data?.needsConfiguration,
    inbox.error,
    inbox.isLoading,
    inbox.revalidate,
  ]);
  const handleOpenMessage = React.useCallback((message) => {
    setMarkReadError(null);
    setSelectedMessage(message);
  }, []);
  const handleCloseMessage = React.useCallback(() => {
    setMarkReadError(null);
    setSelectedMessage(null);
  }, []);
  const handleMarkRead = React.useCallback(async () => {
    if (!selectedUID || isMarkingRead) {
      return;
    }

    setIsMarkingRead(true);
    setMarkReadError(null);

    try {
      await markIMAPMessageRead({
        email,
        password,
        host,
        port,
        mailbox,
        uid: selectedUID,
        connect: connectTCP,
      });

      setReadMessageUIDs((current) => {
        if (current.has(selectedUID)) {
          return current;
        }

        const next = new Set(current);
        next.add(selectedUID);
        return next;
      });
      setSelectedMessage(null);
    } catch (error) {
      setMarkReadError(error);
    } finally {
      setIsMarkingRead(false);
    }
  }, [email, host, isMarkingRead, mailbox, password, port, selectedUID]);
  React.useEffect(() => {
    setReadMessageUIDs(new Set());
    setSelectedMessage(null);
    setMarkReadError(null);
  }, [email, host, mailbox]);

  return (
    <Section
      spacing="sm"
      alignment="leading"
      frame={{ maxWidth: Infinity, maxHeight: Infinity }}
    >
      <Header count={unreadCount} colors={theme.colors} onRefresh={inbox.revalidate} />
      <InboxBody state={viewState} onOpenMessage={handleOpenMessage} />
      {selectedMessage ? (
        <MessageDetailsDialog
          message={selectedMessage}
          detail={messageDetail}
          isMarkingRead={isMarkingRead}
          markReadError={markReadError}
          colors={theme.colors}
          onClose={handleCloseMessage}
          onMarkRead={handleMarkRead}
        />
      ) : null}
    </Section>
  );
}
