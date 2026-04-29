import assert from "node:assert/strict";
import { test } from "node:test";

import { normalizeEmailMessages } from "../../widgets/email/src/utils.mjs";
import {
  fetchIMAPMessageDetail,
  fetchUnreadIMAPMessages,
  markIMAPMessageRead,
  parseFetchResponse,
  parseMessageDetailResponse,
  parseSearchResponse,
  watchIMAPMailbox,
} from "../../widgets/email/src/imap-client.mjs";

const encoder = new TextEncoder();

function createAbortError() {
  const error = new Error("The operation was aborted.");
  error.name = "AbortError";
  return error;
}

function createIMAPSocket(chunks = [], options = {}) {
  const writes = [];
  const pendingReads = [];

  function push(chunk) {
    const pending = pendingReads.shift();
    if (pending) {
      pending.resolve(chunk == null ? null : encoder.encode(chunk));
      return;
    }

    chunks.push(chunk);
  }

  return {
    writes,
    push,
    socket: {
      async write(value) {
        writes.push(value);
        options.onWrite?.(value, push);
      },
      async read({ signal } = {}) {
        if (chunks.length > 0) {
          const next = chunks.shift();
          return next == null ? null : encoder.encode(next);
        }

        if (signal?.aborted) {
          throw createAbortError();
        }

        return new Promise((resolve, reject) => {
          const pending = { resolve, reject };
          pendingReads.push(pending);
          signal?.addEventListener(
            "abort",
            () => {
              const index = pendingReads.indexOf(pending);
              if (index >= 0) {
                pendingReads.splice(index, 1);
              }
              reject(createAbortError());
            },
            { once: true },
          );
        });
      },
      async close() {
        writes.push("CLOSE");
      },
    },
  };
}

test("normalizeEmailMessages trims rows and rejects invalid payloads", () => {
  assert.deepEqual(
    normalizeEmailMessages([
      null,
      { id: "", sender: "Skip", subject: "Missing id" },
      { id: "one", sender: "  Inbox  ", subject: "  Hello  ", tint: "", unread: false },
    ]),
    [
      {
        id: "one",
        sender: "Inbox",
        subject: "Hello",
        avatar: "I",
        tint: "#FA757A",
        unread: false,
      },
    ]
  );
});

test("IMAP parser extracts unread sequence ids and message headers", () => {
  assert.deepEqual(parseSearchResponse("* SEARCH 2 4 5\r\nA0001 OK done\r\n"), ["2", "4", "5"]);

  const firstHeaders = "From: Design <design@example.com>\r\nSubject: Review notes\r\n\r\n";
  const secondHeaders = "From: \"Linear\" <linear@example.com>\r\nSubject: =?utf-8?Q?Issues_assigned?=\r\n\r\n";
  const response = [
    `* 4 FETCH (UID 104 BODY[HEADER.FIELDS (FROM SUBJECT)] {${firstHeaders.length}}\r\n${firstHeaders})`,
    `* 5 FETCH (UID 105 BODY[HEADER.FIELDS (FROM SUBJECT)] {${secondHeaders.length}}\r\n${secondHeaders})`,
    "A0004 OK FETCH completed",
    "",
  ].join("\r\n");

  assert.deepEqual(
    parseFetchResponse(response).map(({ uid, sender, subject, avatar }) => ({ uid, sender, subject, avatar })),
    [
      { uid: "105", sender: "Linear", subject: "Issues assigned", avatar: "L" },
      { uid: "104", sender: "Design", subject: "Review notes", avatar: "D" },
    ]
  );
});

test("fetchUnreadIMAPMessages logs in and fetches the newest unread headers", async () => {
  const writes = [];
  const encoder = new TextEncoder();
  const firstHeaders = "From: Design <design@example.com>\r\nSubject: Review notes\r\n\r\n";
  const secondHeaders = "From: Figma <figma@example.com>\r\nSubject: Updated prototype\r\n\r\n";
  const chunks = [
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "* SEARCH 2 4 5\r\nA0003 OK SEARCH completed\r\n",
    [
      `* 4 FETCH (UID 4 BODY[HEADER.FIELDS (FROM SUBJECT)] {${firstHeaders.length}}\r\n${firstHeaders})`,
      `* 5 FETCH (UID 5 BODY[HEADER.FIELDS (FROM SUBJECT)] {${secondHeaders.length}}\r\n${secondHeaders})`,
      "A0004 OK FETCH completed",
      "",
    ].join("\r\n"),
  ];

  const result = await fetchUnreadIMAPMessages({
    email: "you@gmail.com",
    password: "app-password",
    host: "imap.gmail.com",
    port: "993",
    mailbox: "INBOX",
    maxRows: "2",
    connect: async () => ({
      async write(value) {
        writes.push(value);
      },
      async read() {
        const next = chunks.shift();
        return next == null ? null : encoder.encode(next);
      },
      async close() {
        writes.push("CLOSE");
      },
    }),
  });

  assert.equal(result.unreadCount, 3);
  assert.deepEqual(
    result.messages.map(({ sender, subject }) => ({ sender, subject })),
    [
      { sender: "Figma", subject: "Updated prototype" },
      { sender: "Design", subject: "Review notes" },
    ]
  );
  assert.match(writes[0], /^A0001 LOGIN "you@gmail.com" "app-password"\r\n$/);
  assert.match(writes[1], /^A0002 SELECT "INBOX"\r\n$/);
  assert.match(writes[2], /^A0003 UID SEARCH UNSEEN\r\n$/);
  assert.match(writes[3], /^A0004 UID FETCH 4,5 \(UID BODY\.PEEK\[HEADER\.FIELDS \(FROM SUBJECT\)\]\)\r\n$/);
  assert.match(writes[4], /^A0005 LOGOUT\r\n$/);
  assert.equal(writes[5], "CLOSE");
});

test("fetchUnreadIMAPMessages rejects when the server closes before a command completes", async () => {
  const writes = [];
  const encoder = new TextEncoder();
  const chunks = [
    "* OK Skylane test IMAP ready\r\n",
    null,
  ];

  await assert.rejects(
    fetchUnreadIMAPMessages({
      email: "you@gmail.com",
      password: "app-password",
      host: "imap.gmail.com",
      port: "993",
      mailbox: "INBOX",
      connect: async () => ({
        async write(value) {
          writes.push(value);
        },
        async read() {
          const next = chunks.shift();
          return next == null ? null : encoder.encode(next);
        },
        async close() {
          writes.push("CLOSE");
        },
      }),
    }),
    /IMAP connection closed before A0001 completed/,
  );

  assert.match(writes[0], /^A0001 LOGIN /);
  assert.match(writes[1], /^A0002 LOGOUT\r\n$/);
  assert.equal(writes[2], "CLOSE");
});

test("fetchUnreadIMAPMessages does not hang when logout write never completes", async () => {
  const writes = [];
  const encoder = new TextEncoder();
  const chunks = [
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 0 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "* SEARCH\r\nA0003 OK SEARCH completed\r\n",
  ];

  const startedAt = Date.now();
  const result = await fetchUnreadIMAPMessages({
    email: "you@gmail.com",
    password: "app-password",
    host: "imap.gmail.com",
    port: "993",
    mailbox: "INBOX",
    connect: async () => ({
      async write(value) {
        writes.push(value);
        if (/LOGOUT/.test(value)) {
          return new Promise(() => {});
        }
      },
      async read() {
        const next = chunks.shift();
        return next == null ? null : encoder.encode(next);
      },
      async close() {
        writes.push("CLOSE");
      },
    }),
  });

  assert.deepEqual(result, {
    messages: [],
    unreadCount: 0,
    needsConfiguration: false,
  });
  assert.ok(Date.now() - startedAt < 1500);
  assert.match(writes[3], /^A0004 LOGOUT\r\n$/);
  assert.equal(writes[4], "CLOSE");
});

test("watchIMAPMailbox enters IDLE and refreshes when mailbox changes", async () => {
  const controller = new AbortController();
  let changes = 0;
  const { socket, writes } = createIMAPSocket([
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "+ idling\r\n",
    "* 6 EXISTS\r\n",
  ], {
    onWrite(value, push) {
      if (value === "DONE\r\n") {
        push("A0003 OK IDLE completed\r\n");
      }
    },
  });

  await assert.rejects(
    watchIMAPMailbox({
      email: "you@gmail.com",
      password: "app-password",
      host: "imap.gmail.com",
      port: "993",
      mailbox: "INBOX",
      connect: async () => socket,
      signal: controller.signal,
      onChange() {
        changes += 1;
        controller.abort();
      },
    }),
    { name: "AbortError" },
  );

  assert.equal(changes, 1);
  assert.match(writes[0], /^A0001 LOGIN "you@gmail.com" "app-password"\r\n$/);
  assert.match(writes[1], /^A0002 SELECT "INBOX"\r\n$/);
  assert.match(writes[2], /^A0003 IDLE\r\n$/);
  assert.equal(writes[3], "DONE\r\n");
  assert.equal(writes.at(-1), "CLOSE");
});

test("watchIMAPMailbox renews IDLE without refreshing", async () => {
  const controller = new AbortController();
  let readyCount = 0;
  let changes = 0;
  const { socket, writes } = createIMAPSocket([
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "+ idling\r\n",
  ], {
    onWrite(value, push) {
      if (value === "DONE\r\n" && writes.some((write) => /^A0003 IDLE/.test(write))) {
        push("A0003 OK IDLE completed\r\n");
      }
      if (/^A0004 IDLE/.test(value)) {
        push("+ idling again\r\n");
      }
    },
  });

  await assert.rejects(
    watchIMAPMailbox({
      email: "you@gmail.com",
      password: "app-password",
      host: "imap.gmail.com",
      port: "993",
      mailbox: "INBOX",
      connect: async () => socket,
      signal: controller.signal,
      idleRenewMs: 10,
      onReady() {
        readyCount += 1;
        if (readyCount === 2) {
          controller.abort();
        }
      },
      onChange() {
        changes += 1;
      },
    }),
    { name: "AbortError" },
  );

  assert.equal(readyCount, 2);
  assert.equal(changes, 0);
  assert.match(writes[2], /^A0003 IDLE\r\n$/);
  assert.equal(writes[3], "DONE\r\n");
  assert.match(writes[4], /^A0004 IDLE\r\n$/);
  assert.equal(writes[5], "DONE\r\n");
  assert.equal(writes.at(-1), "CLOSE");
});

test("watchIMAPMailbox aborts during IDLE with best-effort DONE", async () => {
  const controller = new AbortController();
  const { socket, writes } = createIMAPSocket([
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "+ idling\r\n",
  ]);

  await assert.rejects(
    watchIMAPMailbox({
      email: "you@gmail.com",
      password: "app-password",
      host: "imap.gmail.com",
      port: "993",
      mailbox: "INBOX",
      connect: async () => socket,
      signal: controller.signal,
      onReady() {
        controller.abort();
      },
    }),
    { name: "AbortError" },
  );

  assert.match(writes[2], /^A0003 IDLE\r\n$/);
  assert.equal(writes[3], "DONE\r\n");
  assert.equal(writes[4], "CLOSE");
});

test("watchIMAPMailbox rejects when an IMAP command fails", async () => {
  const { socket } = createIMAPSocket([
    "* OK Skylane test IMAP ready\r\n",
    "A0001 NO LOGIN failed\r\n",
  ]);

  await assert.rejects(
    watchIMAPMailbox({
      email: "you@gmail.com",
      password: "app-password",
      host: "imap.gmail.com",
      port: "993",
      mailbox: "INBOX",
      connect: async () => socket,
    }),
    /A0001 NO LOGIN failed/,
  );
});

test("fetchIMAPMessageDetail fetches the full UID body without marking the message read", async () => {
  const writes = [];
  const encoder = new TextEncoder();
  const body = "Hello=\r\n there=21\r\n";
  const chunks = [
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    `* 4 FETCH (UID 5 BODY[TEXT]<0> {${body.length}}\r\n${body})\r\nA0003 OK FETCH completed\r\n`,
  ];

  const result = await fetchIMAPMessageDetail({
    email: "you@gmail.com",
    password: "app-password",
    host: "imap.gmail.com",
    port: "993",
    mailbox: "INBOX",
    uid: "5",
    connect: async () => ({
      async write(value) {
        writes.push(value);
      },
      async read() {
        const next = chunks.shift();
        return next == null ? null : encoder.encode(next);
      },
      async close() {
        writes.push("CLOSE");
      },
    }),
  });

  assert.deepEqual(result, { body: "Hello there!" });
  assert.match(writes[2], /^A0003 UID FETCH 5 \(BODY\.PEEK\[TEXT\]\)\r\n$/);
  assert.match(writes[3], /^A0004 LOGOUT\r\n$/);
  assert.equal(writes[4], "CLOSE");
});

test("markIMAPMessageRead explicitly stores the seen flag for a UID", async () => {
  const writes = [];
  const encoder = new TextEncoder();
  const chunks = [
    "* OK Skylane test IMAP ready\r\n",
    "A0001 OK LOGIN completed\r\n",
    "* 5 EXISTS\r\nA0002 OK SELECT completed\r\n",
    "A0003 OK STORE completed\r\n",
  ];

  const result = await markIMAPMessageRead({
    email: "you@gmail.com",
    password: "app-password",
    host: "imap.gmail.com",
    port: "993",
    mailbox: "INBOX",
    uid: "5",
    connect: async () => ({
      async write(value) {
        writes.push(value);
      },
      async read() {
        const next = chunks.shift();
        return next == null ? null : encoder.encode(next);
      },
      async close() {
        writes.push("CLOSE");
      },
    }),
  });

  assert.equal(result, true);
  assert.match(writes[2], /^A0003 UID STORE 5 \+FLAGS\.SILENT \(\\Seen\)\r\n$/);
  assert.match(writes[3], /^A0004 LOGOUT\r\n$/);
  assert.equal(writes[4], "CLOSE");
});

test("parseMessageDetailResponse strips simple HTML bodies", () => {
  const body = "<p>Hello&nbsp;<strong>there</strong></p>";
  const response = `* 1 FETCH (BODY[TEXT] {${body.length}}\r\n${body})\r\nA0001 OK done\r\n`;
  assert.deepEqual(parseMessageDetailResponse(response), {
    body: "Hello there",
  });
});

test("parseMessageDetailResponse removes MIME part headers and wraps long tokens", () => {
  const token = "cbfc7efa654ceca37cb9bd44e6169015c0c50e60136adce41a45b123f0f6";
  const body = [
    "Content-Transfer-Encoding: quoted-printable",
    "Content-Type: text/plain; charset=utf-8",
    "",
    `Thanks -- ${token}`,
  ].join("\r\n");
  const response = `* 1 FETCH (BODY[TEXT] {${body.length}}\r\n${body})\r\nA0001 OK done\r\n`;

  assert.deepEqual(parseMessageDetailResponse(response), {
    body: "Thanks -- cbfc7efa654ceca37cb9bd44 e6169015c0c50e60136adce4 1a45b123f0f6",
  });
});

test("parseMessageDetailResponse skips attachment MIME parts", () => {
  const body = [
    "--skylane-boundary",
    "Content-Type: text/plain; charset=utf-8",
    "Content-Transfer-Encoding: quoted-printable",
    "",
    "Here is the readable message=21",
    "--skylane-boundary",
    "Content-Type: application/pdf; name=\"invoice.pdf\"",
    "Content-Disposition: attachment; filename=\"invoice.pdf\"",
    "Content-Transfer-Encoding: base64",
    "",
    "JVBERi0xLjQKJcTl8uXrp",
    "--skylane-boundary--",
    "",
  ].join("\r\n");
  const response = `* 1 FETCH (BODY[TEXT] {${body.length}}\r\n${body})\r\nA0001 OK done\r\n`;

  assert.deepEqual(parseMessageDetailResponse(response), {
    body: "Here is the readable message!",
  });
});

test("parseMessageDetailResponse skips non-text inline MIME parts with names", () => {
  const body = [
    "--skylane-boundary",
    "Content-Type: text/html; charset=utf-8",
    "",
    "<p>Hello&nbsp;there</p>",
    "--skylane-boundary",
    "Content-Type: image/png; name=\"logo.png\"",
    "Content-Disposition: inline; filename=\"logo.png\"",
    "Content-Transfer-Encoding: base64",
    "",
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB",
    "--skylane-boundary--",
    "",
  ].join("\r\n");
  const response = `* 1 FETCH (BODY[TEXT] {${body.length}}\r\n${body})\r\nA0001 OK done\r\n`;

  assert.deepEqual(parseMessageDetailResponse(response), {
    body: "Hello there",
  });
});

test("fetchUnreadIMAPMessages reports missing configuration without connecting", async () => {
  let didConnect = false;
  const result = await fetchUnreadIMAPMessages({
    host: "imap.gmail.com",
    email: "",
    password: "",
    connect: async () => {
      didConnect = true;
    },
  });

  assert.deepEqual(result, {
    messages: [],
    unreadCount: 0,
    needsConfiguration: true,
  });
  assert.equal(didConnect, false);
});
