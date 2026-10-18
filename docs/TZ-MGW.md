# Technical Specification: Message Gateway (Haskell)

*Project Specification v0.1 · October 18, 2026 · Structure: Jati (Thesis → Rationale → Example → Counterexample → Distinction → Conclusion)*

| Parameter | Value |
| --- | --- |
| Implementation Language | Haskell (GHC version to be determined in Phase 0) |
| Type | Daemon, library suite, CLI |
| Information status | [Unverified] — see note below |

> **Information status.** [Unverified] The entire document is marked as unverified: information about external protocols, specification numbers, and Haskell packages is based on training data without cross-referencing against primary sources; verification is a Phase 0 task (item 20). Statements such as “the system must” are design decisions, not factual assertions. Markers: **[Conclusion]** — a consequence of other provisions of the Technical Specification; **[Assumption]** — a hypothesis subject to verification; **[Unverified]** — an external fact not cross-checked.
> 

## Part I. Thesis

### 1. Purpose, Objectives, Scope

**1.1. Purpose.** Message Gateway (hereinafter “MGW”) is a long-running process in Haskell that relays messages between heterogeneous transport protocols (chat, teleconferencing, echo-mail, federated feed) via a single canonical representation.

**1.2. Initial Hypothesis and Its Clarification.** The initial hypothesis of the pre-project analysis: adding a transport protocol boils down to writing an adapter, while routing, deduplication, thread mapping, and format conversion remain common across all protocols. [Conclusion] The hypothesis holds strictly only for framing, session management, authentication, retries, and rate limiting. The thread model, identity model (dolls), content degradation rules, delivery mode (push/poll/batch), and provenance contract belong to the common part and are incorporated into the core before the second transport is implemented. This is an architectural invariant of the project.

**1.3. Objectives.**

| ID | Objective | Success Criteria |
| --- | --- | --- |
| G1 | Low cost of the new transport | Adding synthetic reference traffic (Phase 3 output) does not modify `mgw-core`, except for an entry in the adapter registry; the CI is verified using the diff region |
| G2 | No loops or duplicates | In the “full network of 5 endpoints” test, each message is delivered to every other endpoint exactly once, regardless of any permutations or repetitions of input events (property test) |
| G3 | Preservation of thread structure | For transport pairs with compatible thread models, at least 99% of the test corpus responses are mapped to the correct parent [Assumption: the threshold is calibrated] |
| G4 | Accounted-for degradation | Every loss of information is recorded as `a LossNote` in the delivery log; there are no “silent” losses |
| G5 | Reliability | An abnormal termination at any point in the pipeline does not result in the loss of accepted events; delivery resumes after a restart (effectively-once, Section 7.3) |
| G6 | Runs on a single host | One executable file and one SQLite file; external services are limited to the transports themselves |

**1.4. Benefits of the canonical model.** For N transport layers, pairwise integration requires N(N−1) directed translators, while the canonical model requires 2N (decode and encode per transport layer): for N = 5, this is 20 versus 10; for N = 10, it is 90 versus 20 (Hohpe, Woolf, 2003: Canonical Data Model, Channel Adapter, Message Translator).

```latex
N(N-1) \;\longrightarrow\; 2N
```

**1.5. Scope of Application.** The proposed first minimum viable product (MVP): a bidirectional text bridge between a single Matrix homeserver via the Application Service API and a single IRC server via IRCv3. Official specifications confirm the existence of the Matrix Application Service API and IRCv3 message-tags/echo-message; compatibility between specific servers/versions and the selected Haskell packages remains untested and will be verified in Phase 0.[[1]](https://spec.matrix.org/latest/application-service-api)[[2]](https://ircv3.net/specs/extensions/message-tags.html)[[3]](https://ircv3.net/specs/extensions/echo-message.html) NNTP and FTN — after MVP; ActivityPub — a separate subsequent phase. XMPP, Nostr, SMTP, Zulip, Mattermost — v2+. Reference test systems: Synapse and Ergo for MVP; specific versions and compatibility—Phase 0.

**1.6. Not included in the project:** a custom FTN mailer, tosser, Matrix homeserver, IRC server, news server; end-to-end encryption for Matrix (v1 works only with unencrypted rooms). For a complete list of scope limitations, see section 19.

### 2. Terms

| Term | Definition |
| --- | --- |
| Transport | Protocol or messaging system (Matrix, NNTP, FTN, IRC, ActivityPub…) |
| Network | Transport instance: `irc:libera`, `matrix:example.org`, `fido:fidonet` |
| Endpoint | Addressable point on the network: room, newsgroup, echo area, IRC channel, actor, or collection |
| Bridge | A named set of endpoints with a topology that forms a virtual channel |
| Adapter | A package that implements a contract (Codec, Session, Capabilities) for a single transport |
| Event | Canonical exchange unit: message, edit, delete, reaction |
| Puppet | Representation of an external entity in the target network: account, prefix, or synthetic address |
| Provenance | Provenance metadata: hops, gateway tag, fingerprint |
| Capabilities | Endpoint capabilities declaration, based on which the kernel selects transformations |
| LossNote | Record of information lost during degradation |
| Outbox | A persistent outbound delivery queue shared by all adapters |

### 3. Functional Requirements

Priorities: **M** — mandatory, **S** — desirable.

| ID | Requirement | Ex. |
| --- | --- | --- |
| FR-01 | The adapter delivers events in push mode (persistent connection), poll mode (cursor-based polling), or batch mode (packets, spool). The kernel distinguishes between modes only through `Capabilities` | M |
| FR-02 | A native message is decoded into `an Event` by a pure function; a decoding error does not stop the adapter; the event is sent to the dead-letter queue with the reason | M |
| FR-03 | The original native (raw) format is preserved (configurable) for playback and lossless transmission between transports of the same type | S |
| FR-04 | Deduplication by pair (EndpointId, NativeId) | M |
| FR-05 | Each outgoing instance carries a hop label via the target transport’s label carrier; an incoming instance with our label is not rerouted | M |
| FR-06 | For transports without a tag carrier—suppression of the expected echo based on the fingerprint (Section 8.1) | M |
| FR-07 | Messages from the system’s own puppets and the bot are not routed | M |
| FR-08 | Hop limit; when exhausted, messages are discarded with a log entry | M |
| FR-09 | Parent approval via the compliance registry; if a parent is missing, the reference is moved to " `Pending` " with a timeout | M |
| FR-10 | Projection of a thread onto a target model (hierarchy, flat channel, topic, graph) according to the rules in section 8.2 | M |
| FR-11 | Storing source↔target native ID mappings for replies, edits, and deletions | M |
| FR-12 | Register of actors with`trust` levels | M |
| FR-13 | Target-based puppet strategies: `NativePuppet`, `RelayPrefix`, `Synthesized` | M |
| FR-14 | Time-Stable Name Collision Resolution | M |
| FR-15 | Puppet Lifecycle: Creation, Activity, Suspension, and Deletion Due to Inactivity | S |
| FR-16 | Canonical content representation—AST (blocks and inlines), not a string | M |
| FR-17 | Reading and writing CP437, CP866, KOI8-R, CP1251, and UTF-8 encodings (FTN declares the encoding using the CHRS service string [Not verified]) | M |
| FR-18 | `Capabilities-based` degradation accounting for losses; idempotent and does not invent content | M |
| FR-19 | Attachments: link by default (`LinkOnly`); optional media proxy | S |
| FR-20 | Splitting into parts when the limit is exceeded (IRC line, FTN message) while preserving order and numbering | M |
| FR-21 | Bridges are defined declaratively: a set of endpoints and topology (mesh, star, directed) | M |
| FR-22 | Filters by author, text, event type, and size | S |
| FR-23 | Reloading the configuration without losing state (SIGHUP) | S |
| FR-24 | Durable outbox (transactional outbox) for each destination endpoint | M |
| FR-25 | Retry with exponential backoff and jitter; rate limit per endpoint; dead-letter after N attempts | M |
| FR-26 | Batch delivery: accumulation and transmission in batches according to policy (FTN) | M |
| FR-27 | Edits, deletions, and reactions are relayed if the target’s `cpEvents` allow them; otherwise, the policy is `Drop` or `AsText` | S |
| FR-28 | CLI `mgwctl`: status of adapters, queues, dead-letter, replay, and dry-run routes | M |
| FR-29 | Prometheus-format metrics, structured logs with correlation-id, health endpoint | M |
| FR-30 | Replay mode: running saved events through the current configuration without sending them | S |

### 4. Non-functional requirements

| ID | Requirement |
| --- | --- |
| NFR-01 | Reliability: Loss of an accepted event upon ` `kill -9` ` is not permitted. “Accepted” = committed by transaction T1 (Section 7.1) |
| NFR-02 | Recovery: Post-failure restart must take no more than 30 seconds with a queue of up to 100,000 records [Assumption] |
| NFR-03 | Performance: At least 200 events/s and a p95 kernel latency (ingress→outbox) of no more than 50 ms on 2 vCPUs / 2 GiB / SSD in a test with `mgw-adapter-mock` [Assumption: calibrated in Phases 0–1] |
| NFR-04 | Memory: no more than 256 MiB RSS in steady state with 5 adapters and 100 bridges [Assumption] |
| NFR-05 | Security: see item 17; secrets are not stored in plain text in the configuration ( `file:` and `env:` references) |
| NFR-06 | Observability: Every delivery is traceable by `MsgId` from input to output (logs and metrics) |
| NFR-07 | Maintainability: the core is free of I/O in models, degradation logic, the mapper, and the router; property tests for L1–L5 rules; references to specific transports in `mgw-core` are prohibited (verified in CI) |
| NFR-08 | Portability: Linux (x86_64, aarch64); build via Cabal; static linking—optional |
| NFR-09 | GHC policy: the two most recent major branches of the selected snapshot [Assumption]; exact version — Phase 0 |
| NFR-10 | Dependency licenses are compatible with the project license (open issue Q1) |

## Part II. Rationale

### 5. Architecture

**5.1. Principles.**

- **P1.** Pure core, imperative shell: models, degradation, thread mapper, and router are pure functions; I/O is only in adapters, storage, and the supervisor.
- **P2.** Codec (pure) is separated from Session (I/O): the codec is verified by properties and golden files without a network.
- **P3.** The core is controlled by `Capabilities`, not by the transport name.
- **P4.** Lossless pass-through: native fields, which are incomprehensible to the kernel, are stored in the `ExtMap` namespace and returned to a transport of the same type without modification.
- **P5.** Durable outbox: an event is considered accepted only after it is written to the database.
- **P6.** Explicit degradation: the transformation returns a result and a list `of LossNotes`.
- **P7.** Type safety: identifiers are ``newtype``, not raw strings.

**5.2. Structure.**

```
┌───────────────────────── mgw (исполняемый файл) ─────────────────────────┐
│ Config · Supervisor · Admin API/CLI · Metrics · Logging                  │
├──────────────────────────────────────────────────────────────────────────┤
│ mgw-core: Dedup/Provenance → ThreadMapper → IdentityRegistry → Router →  │
│           Transformer(Degrader) → Outbox/Dispatcher                      │
│ mgw-store (SQLite; PostgreSQL — v2)        mgw-model (типы и законы)     │
├──────────────────────────────────────────────────────────────────────────┤
│ mgw-adapter-api: Codec · Session · Capabilities · SendResult             │
├────────┬────────┬────────┬────────┬──────────────┬─────────────────────┤
│ Matrix │  NNTP  │  FTN   │  IRC   │ ActivityPub  │ XMPP · Nostr · …    │
└────────┴────────┴────────┴────────┴──────────────┴─────────────────────┘
```

### 6. Canonical Model

The model is the `mgw-model` package. A thread is represented as a superset of transport models: a DAG of edges plus an optional topic plus a source type. [Conclusion] This representation accommodates the NNTP/FTN hierarchy, flat IRC, `m.thread` Matrix, ActivityPub’s `inReplyTo`, Zulip’s stream+topic pair, and Nostr’s e-tag graph without losing structure upon input; losses are possible only when projecting onto a less rich target, where they are accounted for (`LossNote`).

```haskell
module MGW.Model where
-- P7: идентификаторы — newtype
newtype MsgId         = MsgId UUID            -- внутренний, UUIDv7 (монотонен по времени)
newtype NetworkId     = NetworkId Text        -- irc:libera, matrix:example.org, fido:fidonet
newtype EndpointId    = EndpointId Text       -- канал, комната, группа, эха-область
newtype NativeId      = NativeId ByteString   -- Message-ID, MSGID, event_id, msgid, AP id
newtype BridgeId      = BridgeId Text
newtype GatewayId     = GatewayId Text        -- экземпляр шлюза (для путей хопов)
newtype TransportKind = TransportKind Text    -- открытый тип: новый транспорт не меняет ядро

data Origin = Origin { oEndpoint :: EndpointId, oNative :: NativeId }

data Event
  = EvPost   Post
  | EvEdit   MsgRef Post
  | EvRedact MsgRef (Maybe Text)
  | EvReact  MsgRef Text Bool                 -- ключ реакции, добавлена или снята

data Post = Post
  { pId :: MsgId, pOrigin :: Origin, pBridge :: BridgeId
  , pAuthor :: ActorRef, pCreated :: UTCTime, pReceived :: UTCTime
  , pThread :: ThreadCtx, pContent :: Content, pAttach :: [Attachment]
  , pProv :: Provenance, pExt :: ExtMap }

data ThreadCtx = ThreadCtx
  { tEdges :: [Edge]          -- 0..n: цепочка References, e-теги Nostr, inReplyTo
  , tTopic :: Maybe Text      -- Zulip topic; Subject NNTP/FTN
  , tShape :: ThreadShape }   -- форма источника, нужна для оценки потерь
data Edge        = Edge { eKind :: EdgeKind, eTarget :: MsgRef, eConf :: Confidence }
data EdgeKind    = ReplyTo | Root | QuoteOf | Forward | MentionOf | EdgeExt Text
data Confidence  = Explicit | Heuristic
data MsgRef      = Resolved MsgId | Unresolved Origin   -- отложенное разрешение
data ThreadShape = Hierarchical | Flat | TopicBased | TagGraph

data ActorRef = ActorRef
  { arNetwork :: NetworkId, arNative :: Text
  , arDisplay :: Maybe Text, arTrust :: Trust }
data Trust = Asserted | Authenticated | Cryptographic   -- IRC-ник | сессия | подпись

data Content = Content { cDoc :: Doc, cLang :: Maybe Text, cSrcCharset :: Maybe Charset }
newtype Doc  = Doc [Block]
data Block   = Para [Inline] | Quote [Block] | Code (Maybe Text) Text | Items Bool [[Block]]
data Inline  = Txt Text | Emph [Inline] | Strong [Inline] | Mono Text
             | Link Text [Inline] | Mention ActorRef | Spoiler [Inline] | Br

data Provenance = Provenance
  { pvHops :: [Hop], pvHopLimit :: Int, pvFingerprint :: Fingerprint, pvMark :: Maybe Mark }
data Hop = Hop { hGateway :: GatewayId, hFrom :: NetworkId, hTo :: NetworkId, hAt :: UTCTime }
newtype ExtMap = ExtMap (Map Text ByteString)   -- ключи с пространством имён: ftn.kludge.MSGID

data Capabilities = Capabilities
  { cpRich     :: RichLevel      -- NoMarkup | LightMarkup | HtmlSubset | FullDoc
  , cpThread   :: ThreadShape
  , cpMaxBytes :: Maybe Int      -- на сообщение
  , cpMaxLine  :: Maybe Int      -- на строку (IRC, FTN)
  , cpCharsets :: NonEmpty Charset
  , cpEvents   :: Set EventKind  -- Post | Edit | Redact | React
  , cpAttach   :: AttachPolicy   -- Inline | LinkOnly | Unsupported
  , cpDelivery :: DeliveryMode   -- Realtime | Polled Int | Batched BatchPolicy
  , cpIdentity :: PuppetStrategy -- NativePuppet | RelayPrefix | Synthesized
  , cpMark     :: MarkCarrier }  -- Header | Kludge | Tag | ContentField | NoCarrier
-- Charset, Fingerprint, Mark, Attachment и прочие вспомогательные типы — в mgw-model
```

**Laws (verified by property tests).**

**L1 (round-trip).** For adapter A and a set C_A of events expressible in it:

```latex
\mathrm{decode}_A\bigl(\mathrm{encode}_A(e)\bigr) \sim_A e \qquad \forall e \in \mathcal{C}_A
```

Here, ~_A denotes equivalence modulo the losses declared in adapter A’s `Capabilities`.

**L2 (degradation idempotence).** For any `Capabilities` c:

```latex
\mathrm{deg}_c \circ \mathrm{deg}_c = \mathrm{deg}_c
```

**L3 (no fabrication).** The text of the degradation result consists of fragments of the original text and service markers listed in `LossNote`.

**L4 (Reception idempotence).** Resubmitting the same event does not change the state of the storage or the queue.

**L5 (routing invariance).** An event is not sent to the source endpoint or to an endpoint already present in the hop list.

### 7. The Pipeline and Guarantees

**7.1. Stages.**

1. **Ingress.** The adapter places the native message into a bounded queue (`TBQueue`)—backpressure.
2. **Decode.** Valid messages are decoded into the `Event` list; errors are sent to the dead-letter queue.
3. **Transaction T1** (one database transaction): deduplication (FR-04–FR-08); event and native ID mapping; parent resolution (matched parents are linked; unmatched ones receive a `Pending` status); route determination (fan-out); insertion of outbox records for each target endpoint.
4. **Dispatch.** The endpoint dispatcher reads the outbox, constructs `an OutboundPlan` at the time of sending (Section 7.2), and sends it via `Session`.
5. **Transaction T2.** Records the source↔target native ID match; marks the outbox record as `Done`.

**7.2. The transformation is performed at the time of sending.** [Conclusion] The response must reference the parent’s native identifier in the target network, but this is only known after the parent has been delivered. Therefore, `the Transformer` (degradation, thread projection, dummy selection) is called by the dispatcher at the time of sending. If the parent for the target has not yet been delivered, the record moves to ` `WaitingParent` ` with a timeout; once the timeout expires, the message is sent as an “orphan” with `a `LossNote``.

**7.3. Delivery Guarantees.** Outbound delivery is at-least-once; combined with an idempotent receiver, this results in effectively-once:

```latex
\text{at-least-once} + \text{idempotent receiver} \;\Rightarrow\; \text{effectively-once}
```

Idempotency is ensured by the MGW deduplicator upon receipt and by the idempotency of the destination side, where applicable. [Unverified] Based on training data: Matrix—transaction ID in the send request; NNTP—server rejection of duplicate Message-IDs; FTN—duplicate detection by MSGID in the tosser; ActivityPub — activity identifier; IRC — no idempotence. For transports without idempotence where the outcome of sending is uncertain (failure between sending and T2), the endpoint policy is explicitly set to: `DropOnUnknown` (default for real-time; [Conclusion] a duplicate in a chat is worse than a loss) or `RetryOnUnknown`.

**7.4. Order.** FIFO is guaranteed within (bridge, source endpoint): processing is sharded by `BridgeId`. The “parent before child” causal order is ensured by the `WaitingParent` state for tasks with `a cpThread` other than `Flat`. There is no global order.

**7.5. Concurrency.** The supervisor tree for `async`: root supervisor → adapter supervisor (restart with exponential delay and jitter) → `Session` threads. The kernel’s worker pool is sharded by `BridgeId`; endpoint dispatchers are independent, each with its own token bucket. Correct termination: stop accepting requests, drain queues, close sessions (`bracket`, `withAsync`; “hanging” `forkIOs` are not allowed).

### 8. Core Subsystems

**8.1. Deduplication and provenance.** Three levels of protection—from precise to approximate:

1. **Exact key.** The pair (EndpointId, NativeId) is unique; a duplicate stops the pipeline (L4).
2. **Gateway tag.** Each outgoing instance carries `a Mark` (GatewayId, MsgId, number of hops) via the destination’s `MarkCarrier`: header (NNTP), kludge string (FTN), client tag (IRC), content field (Matrix), object extension (ActivityPub). An incoming message marked with our GatewayId is not routed. Tag field names are selected in Phase 0 [Assumption].
3. **Expected echo.** For transports without a tag carrier (IRC without tags), the core stores fingerprints only of its own outgoing deliveries to a given endpoint within a window of W; an incoming event with a matching fingerprint is suppressed as an echo.

Fingerprint:

```latex
\mathrm{fp} = \mathrm{trunc}_{128}\Bigl(\mathrm{SHA\text{-}256}\bigl(\mathrm{norm}(t)\,\Vert\,a\,\Vert\,\lfloor \tau / W \rfloor\bigr)\Bigr)
```

Here, norm(t) is the sent text in normalized form (Unicode NFC, collapsed spaces, without markup; for split messages—for each part), a is the sender in the target network (bot or dummy), τ is the time, and W is the window (default 120 s; the adjacent window is also checked). The probability of a random collision with n stored fingerprints is estimated using the birthday bound:

```latex
p \approx \frac{n^{2}}{2^{129}}, \qquad n = 10^{9} \;\Rightarrow\; p \sim 2^{-69}
```

[Conclusion] The third-level region is intentionally narrow (only echoes of its own deliveries): a false positive is possible only if a real user’s identical text appears at the same endpoint within the window W.

**8.2. Thread Mapper.** Input: `the` source’s `ThreadCtx`; output: a projection for the target. Resolution: each edge marked as `Unresolved` is looked up in the mapping registry (EndpointId, NativeId); if not found, the state becomes `Pending(ref, deadline)`. Default TTL: 15 minutes for real-time sources and 72 hours for batch sources [Assumption]. Cycles in the reference chain are detected and broken; depth is limited (default 100).

| Target Form | Projection rule |
| --- | --- |
| Hierarchical (NNTP, FTN) | Native ancestor identifiers → `References` (NNTP: chain truncated to header length; root and nearest ancestors are preserved) or kludge REPLY (FTN: one immediate parent). Subject — root subject prefixed with  `Re:`  |
| Flat (IRC) | Parent is unavailable; with the `QuoteReply` policy, a short quote-reference is added at the beginning; the IRCv3 reply tag is used when supported [Unverified] |
| TopicBased (Zulip) | `tTopic` is taken from the root topic; if absent, `DefaultTopic` from the configuration |
| TagGraph (Nostr) | Tags `with` root and reply markers per NIP-10 [Unverified] |
| Matrix | `m.in_reply_to`; for an explicit thread—the `m.thread` relationship [Not verified] |
| ActivityPub | `inReplyTo` to the native identifier of the parent object |

Edges are not reconstructed from flat forms. The “nickname at the beginning of the line” heuristic can be optionally enabled with `Confidence = Heuristic`; it is disabled by default. [Conclusion] False connections in hierarchical networks are more harmful than the absence of connections.

**8.3. Identity and Puppet Registry.** Puppet lifecycle: `Unprovisioned → Provisioning → Active ⇄ Suspended → Retired`. Creation occurs upon the author’s first message; `Suspended` —in case of errors or blocking at the target; `Retired` —due to inactivity (TTL is configurable), only for dummies occupying the target’s resources.

| Strategy | Essence | Application |
| --- | --- | --- |
| `NativePuppet` | A separate account or actor for each external author | Matrix (virtual users of the service app), ActivityPub [Not verified] |
| `RelayPrefix` | Messages are sent by a single bot; the author is indicated by a prefix in the text | IRC, Zulip, Mattermost |
| `Synthesized` | The “From” field is generated from the author’s name and the gateway address | NNTP (From), FTN (sender’s name and gateway address) |

Rules: The puppet name is deterministic (a sanitized display name plus, in case of a collision, a stable suffix derived from the hash of the network and native author pair) and does not change over time; the name is sanitized to meet the destination’s constraints (length, character set, encoding); `Trust` is carried along with `ActorRef` and is not elevated during relaying — [Conclusion] an IRC nickname (`Asserted`) cannot be used for authentication on other networks; Merging identities across networks (ActorLink) is outside the scope of v1, but storage should not require model migration when it is added.

**8.4. Router.** A bridge is a set of endpoints and a topology: `Mesh` (everyone connected to everyone), `Star` (spokes through a central endpoint), `Directed` (explicit edges, including unidirectional ones). Pure function: `route :: Config -> Event -> [EndpointId]`; applies filters (FR-22) and excludes the source and endpoints from the hop list (L5).

**8.5. Transformer and Degradation.** Transformation: thread projection → puppet selection → content degradation → splitting by limits → tag attachment → `OutboundPlan` with a `LossNote` list.

| Element | Target without annotation | Lightly Marked Target |
| --- | --- | --- |
| Strong, Emph | `*text*`, `_text_`, or no highlighting—as per policy | Native target annotation |
| Code block | 4-space indent | Enclosed block |
| Link | `text (url)` | Native link |
| Quote | Prefix  `>   for`  each line | Native quote |
| Spoiler | `[spoiler: text]` | Native spoiler if available |
| Mention | `@name` in target notation | Native doll mention |
| Attachment | `[file: name — url]` (`LinkOnly`) | Native attachment |
| Character outside the target encoding | `Translit`, `Replace`, or `Fail` policy; loss is recorded in `LossNote` | Same |

Splitting by limits occurs at word boundaries, in bytes (code points and graphemes are not split), with parts numbered (1/3). The FTN line width is configurable; the default is 79 columns [Unverified: typical network convention]. The IRC line limit includes the prefix and tags [Unverified: 512 bytes including CRLF].

**8.6. Delivery.** States of an outbox record: `Queued → Sending → Done`; `Retry`; `WaitingParent`; `SendUnknown`; `Dead` (dead-letter). The delay of the kth retry is an exponential function with jitter:

```latex
t_k = \min\bigl(t_{\max},\; t_0 \cdot 2^{k}\bigr) \cdot u, \qquad u \sim U(0.5,\,1)
```

Here, t_0 is the initial delay, and t_max is the upper bound. For `Batched endpoints`, records are accumulated up to `maxSize` or `maxAge` and transmitted to the adapter in a packet; the formation of physical FTN packets is the adapter’s responsibility—the kernel is only aware of the policy.

### 9. Adapter Contract

The adapter consists of `a` pure `Codec`, `an` effect-based `Session`, and a `Capabilities` declaration (P2 principle):

```haskell
data Codec n = Codec
  { decode :: n -> Either DecodeError [Event]
  , encode :: Capabilities -> OutboundPlan -> Either EncodeError [n] }

data Session n = Session
  { sRun    :: (n -> IO ()) -> IO ()        -- ingress: коллбэк на каждое нативное сообщение
  , sSend   :: n -> IO SendResult
  , sLookup :: Mark -> IO (Maybe NativeId)  -- опционально: была ли отправка (для SendUnknown)
  , sHealth :: IO Health
  , sClose  :: IO () }

data SendResult
  = Sent NativeId
  | Retryable Reason (Maybe NominalDiffTime)  -- повтор, возможно с подсказкой Retry-After
  | Permanent Reason                          -- в dead-letter
  | Unknown                                   -- исход неизвестен: политика эндпоинта

data Adapter = forall n. Adapter
  { aKind :: TransportKind, aCaps :: Capabilities
  , aCodec :: Codec n, aSession :: Session n }

data AdapterFactory = AdapterFactory
  { afKind  :: TransportKind
  , afBuild :: Value -> CursorStore -> IO Adapter }

-- Единственное место, где ядро знает об адаптерах; собирается в mgw-app (флаги cabal)
adapterRegistry :: [AdapterFactory]
```

**Adapter Requirements.**

- **A1.** There is no direct access to the core database; cursors (NNTP last message number, Matrix synchronization token, processed FTN files) are accessible only through `CursorStore`.
- **A2.** Ingress goes through a limited queue; `sRun` is blocked upon overflow (backpressure).
- **A3.** The codec is clean and total: any input results in `a Right` or `Left DecodeError`; there are no exceptions.
- **A4.** Unknown native fields are stored in `ExtMap` (P4).
- **A5.** `Capabilities` are declared honestly; discrepancies between declaration and behavior are detected by the conformance suite.
- **A6.** Network errors are `Retryable`; protocol errors that cannot be resolved by retrying are `Permanent`; a failure after sending without acknowledgment is `Unknown`.
- **A7.** The adapter registry is the only point where the kernel “knows” about adapters (G1).

**Conformance set.** The `mgw-conformance` package is a parameterized set of properties: L1 for the codec; completeness `of decoding` on garbage input (fuzzing); alignment `of Capabilities` with actual limits; idempotence `of sSend` when retried with the same key where declared; behavior upon connection termination. An adapter is accepted into the project if it passes the set of tests.

### 10. Roadmap Adapters

The MVP includes only Matrix and IRC; NNTP, FTN, and ActivityPub are described below as subsequent adapters, not mandatory requirements for the first release.

| Adapter | Reception and Delivery | Identity | Thread | Label Carrier |
| --- | --- | --- | --- | --- |
| Matrix | push: application-service transactions; sent via HTTP | `NativePuppet` | `m.in_reply_to`, `m.thread` | `content` field |
| NNTP | poll (client mode); peer — v2 | `Synthesized` | Hierarchical (`References`) | header |
| FTN | batch: packet spool | `Synthesized` | Hierarchical (REPLY, MSGID) | kludge string |
| IRC | push: bot connection | `RelayPrefix` (optional `NativePuppet`) | Flat | client tag or fingerprint |
| ActivityPub | push to inbox; outgoing via queue | `NativePuppet` | `inReplyTo` | object property |

**10.1. Matrix.** [Unverified] Integration — as an application service (Application Service API): registration with the home server (registration file, tokens, virtual user namespace), receiving events via transaction calls from the home server to the MGW (`warp`), sending via the Client-Server API on behalf of virtual users. Idempotence: transaction ID—a deterministic function of `MsgId` and endpoint. Edits and deletions are displayed in `EvEdit` and `EvRedact`. v1 limitations: unencrypted rooms only; homeserver limits are enforced via a token bucket. Risks: specification changes; historical backfill is not imported.

**10.2. NNTP.** Version 1—client mode [Assumption: easier to develop]: reading by cursor (`GROUP`, `OVER`, `ARTICLE`) and writing (`POST`). Version 2 — peer mode (`IHAVE`, `CHECK`, `TAKETHIS`) for speed and accurate `Path` transmission. Headers: `Message-ID` is generated by the MGW in the gateway domain; `References`, `Subject`, `Newsgroups`, `From` (`Synthesized`), `Date`, `Path` (with gateway tag), `Content-Type` with charset, service header for the tag; non-Latin headers are encoded according to RFC 2047 [Unverified]. Control messages `(cancel)` are displayed in `EvRedact` only according to an explicit policy (protection against cancel spam). The cursor is a pair (group, last article number) with a check for group renumbering. Risks: group recreation and renumbering; large articles (attachments— `LinkOnly` only).

**10.3. FTN.** Version 1—spool integration: MGW acts as the gateway for the binkd and hpt stack (Husky family) [Unverified: compatibility]. Incoming `.pkt files` are read from a directory populated by the tosser based on area routing; outgoing `.pkt files` are written to the tosser’s scan directory. The MGW does not implement a mailer and does not generate `SEEN-BY` or `PATH` —these are managed by the tosser. Version 2—direct interaction with the message database (JAM or Squish) [Not verified].

- Codec: Type-2+ format packets [Not verified: FTS-0001], echomail messages (`AREA:`), kludge strings `MSGID`, `REPLY`, `PID`, `TID`, `CHRS`, Origin, and Tearline.
- Atomicity: A file is moved to the processed archive only after T1; in the event of a failure, reprocessing is prevented by deduplication based on `the MSGID`.
- `The MSGID` of outgoing messages is generated by MGW (gateway address plus a unique number); `REPLY` specifies `the` parent’s `MSGID`.
- Encoding: incoming—per `CHRS`; outgoing—per region setting (default CP866, or UTF-8 if the network allows it) [Unverified].
- The sender’s name is limited to the field length of the format [Unverified: 36 bytes]; `“Synthesized”` truncates the name while preserving the suffix.
- Risks: `MSGID` collisions on older clients; missing `MSGID` (fallback: header and body hash); corrupted packets (quarantine directory); non-standard encodings.

**10.4. IRC.** `Session` — a client-side TLS connection with custom string parsing, including IRCv3 tags [Assumption: custom parsing is simpler than an external dependency]. [Untested] Utilizes `message-tags`, `server-time`, `echo-message`, `msgid`, and SASL capabilities. `RelayPrefix`: `<author> text`; `NativePuppet` for each author—optional (a separate connection is expensive). Flood control—token bucket with a queue; reconnection with exponential backoff. No edits or deletions: for `EvEdit`, the policy is `AsText` (a string of the form `“author edited: …”`) or `Drop`. A tag is a client-side tag if the server skips it; otherwise, it is a fingerprint (section 8.1).

**10.5. ActivityPub.** MGW acts as a “bridge” server: inbox via `warp`, outgoing delivery via `an HTTP client` with a queue. Actors: `NativePuppet` —a Person actor for an external author or a single Group actor for the bridge (configurable) [Assumption]. [Untested] HTTP signatures are required in both directions; draft-cavage and RFC 9421 are supported, since Mastodon-compatible servers have historically used draft-cavage. WebFinger and minimal NodeInfo are implemented for discovery. Mapping: `Create(Note)` → `EvPost`, `Update` → `EvEdit`, `Delete` → `EvRedact`; thread — `inReplyTo`. Security: SSRF (prohibition of private addresses when loading keys and objects), size limits, key cache with TTL, domain limits, domain blocklist. Risks: Highest complexity and attack surface—hence Phase 4, after the core has stabilized.

### 11. Storage

**11.1. Requirements.** T1 and T2 transactions (section 7.1). SQLite in WAL mode with a single writer (records are serialized in a single thread)—[Conclusion] this eliminates lock conflicts. `Store` interface—function calls (handle); a second backend (PostgreSQL) can be connected without modifying the core. Migrations—numbered SQL files, applied at startup; version stored in ` `schema_migrations``.

**11.2. Main Tables.**

```sql
CREATE TABLE messages (
  msg_id        BLOB PRIMARY KEY,           -- UUIDv7
  bridge_id     TEXT NOT NULL,
  origin_ep     TEXT NOT NULL,
  origin_native BLOB NOT NULL,
  kind          TEXT NOT NULL,              -- post, edit, redact, react
  author_id     INTEGER NOT NULL REFERENCES actors(actor_id),
  created_at    INTEGER NOT NULL,           -- unix, мкс
  received_at   INTEGER NOT NULL,
  body_json     TEXT NOT NULL,              -- Content, ThreadCtx, Ext в каноническом JSON
  raw           BLOB,                       -- нативная форма (опционально)
  UNIQUE (origin_ep, origin_native)         -- FR-04
);
CREATE TABLE native_ids (                   -- соответствия msg_id и нативных id
  msg_id    BLOB NOT NULL REFERENCES messages(msg_id),
  endpoint  TEXT NOT NULL,
  native_id BLOB NOT NULL,
  direction TEXT NOT NULL,                  -- in, out
  UNIQUE (endpoint, native_id)
);
CREATE TABLE edges (
  msg_id BLOB NOT NULL, kind TEXT NOT NULL, confidence TEXT NOT NULL,
  target_msg BLOB,                          -- NULL, пока ребро не разрешено
  target_ep TEXT, target_native BLOB,       -- Unresolved Origin
  deadline INTEGER                          -- TTL состояния Pending
);
CREATE TABLE actors (
  actor_id INTEGER PRIMARY KEY, network TEXT NOT NULL, native TEXT NOT NULL,
  display TEXT, trust TEXT NOT NULL, UNIQUE (network, native)
);
CREATE TABLE puppets (
  actor_id INTEGER NOT NULL REFERENCES actors(actor_id),
  target_network TEXT NOT NULL, puppet_native TEXT NOT NULL,
  state TEXT NOT NULL, last_used INTEGER,
  PRIMARY KEY (actor_id, target_network)
);
CREATE TABLE outbox (
  id INTEGER PRIMARY KEY, msg_id BLOB NOT NULL, endpoint TEXT NOT NULL,
  state TEXT NOT NULL,                      -- queued, sending, done, retry, waiting_parent, send_unknown, dead
  attempts INTEGER NOT NULL DEFAULT 0, next_attempt INTEGER,
  idem_key BLOB NOT NULL, last_error TEXT,
  UNIQUE (msg_id, endpoint)                 -- одна доставка на цель
);
CREATE TABLE echo_fp (endpoint TEXT NOT NULL, fp BLOB NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE cursors (adapter TEXT NOT NULL, key TEXT NOT NULL, value BLOB, PRIMARY KEY (adapter, key));
CREATE TABLE loss_log (msg_id BLOB, endpoint TEXT, note TEXT, at INTEGER);
CREATE TABLE dead_letters (id INTEGER PRIMARY KEY, adapter TEXT, payload BLOB, reason TEXT, at INTEGER);
CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at INTEGER);
```

**11.3. Storage and privacy.** The retention period for `raw` and completed outbox records is configurable (default 90 days) [Assumption]; `echo_fp` is cleared upon `expiration`. Deletion (`EvRedact`) clears ` `body_json` ` and ``raw``, but preserves ` `native_ids` ` for thread consistency.

### 12. Configuration

Format—YAML; parsed into typed structures via `Aeson` with clear error messages; checked at startup; startup fails if the configuration is incorrect. Secrets—only via ``file:`` and ``env:`` references (NFR-05). Bridges and policies are reloaded upon `SIGHUP`; adapters with unchanged `config` are not restarted (FR-23).

```yaml
gateway:
  id: mgw-1
  store: { kind: sqlite, path: /var/lib/mgw/mgw.db }
  hop_limit: 4
  echo_window_sec: 120

networks:
  - id: irc:libera
    transport: irc
    config: { host: irc.example.org, port: 6697, tls: true, nick: mgw, sasl_password: file:/etc/mgw/irc.pass }
  - id: matrix:example.org
    transport: matrix
    config: { homeserver: https://matrix.example.org, as_token: env:MGW_AS_TOKEN, hs_token: env:MGW_HS_TOKEN, listen: 127.0.0.1:9100 }
  - id: nntp:local
    transport: nntp
    config: { host: 127.0.0.1, port: 119, domain: gw.example.org, poll_sec: 30 }
  - id: fido:fidonet
    transport: ftn
    config: { inbound: /var/spool/mgw/in, outbound: /var/spool/mgw/out, gate_address: Z:N/F.P, charset: cp866 }

bridges:
  - id: general
    topology: mesh
    endpoints:
      - { network: irc:libera,         endpoint: '#general' }
      - { network: matrix:example.org, endpoint: '!roomid:example.org' }
      - { network: nntp:local,         endpoint: local.general }
      - { network: fido:fidonet,       endpoint: GENERAL }
    policy:
      thread_pending_ttl: { realtime: 15m, batch: 72h }
      on_unknown_send: drop
      degrade: { unicode: translit, attachments: link }
```

### 13. Technology Stack and Project Structure

**13.1. Packages** (multi-package Cabal project).

| Package | Purpose | Depends on |
| --- | --- | --- |
| `mgw-model` | Types, laws, test generators | — |
| `mgw-adapter-api` | `Codec`, `Session`, `Capabilities`, `SendResult` | model |
| `mgw-store` | `Store` interface, SQLite backend, migrations | model |
| `mgw-core` | Pipeline, subsystems (item 8), supervisor | model, store, adapter-api |
| `mgw-adapter-{mock,irc,matrix,nntp,ftn,activitypub}` | Adapters | adapter-api, model |
| `mgw-conformance` | Set of properties for adapters | adapter-api |
| `mgw-app` | `mgw` executable: configuration, registry, admin API | all |
| `mgw-ctl` | `mgwctl` CLI | model (admin protocol) |

`mgw-core` does not depend on any `mgw-adapter-*`; the dependency graph is verified in CI (NFR-07).

**13.2. Dependency Candidates.** [Not Verified] The availability, validity, and compatibility of packages are verified in Phase 0.

| Scope | Candidate |
| --- | --- |
| Concurrency | `base`, `stm`, `async`, `unliftio` |
| Data | `text`, `bytestring`, `containers`, `time`, `uuid` |
| JSON, YAML | `aeson`, `yaml` |
| Parsing | `attoparsec` or `megaparsec` |
| HTTP | `http-client`, `http-client-tls`, `warp`, `wai` |
| Network and TLS | `network`, `tls` (or `connection` wrapper) |
| Database | `sqlite-simple` (v1); `postgresql-simple` or `hasql` (v2) |
| Cryptography | `crypton` (SHA-256, signatures) |
| Encodings | `text-icu` or `iconv`; custom CP437, CP866, KOI8-R, and CP1251 tables as a fallback |
| Logs, metrics | `katip` or `co-log`; `prometheus-client` |
| Tests | `tasty`, `tasty-hunit`, `tasty-golden`, `hedgehog`, or `QuickCheck` |
| Build and styling | `cabal`; optionally Nix flake; `ormolu` or `fourmolu`; `hlint` |

**13.3. Dependency Acceptance Criteria (Phase 0).** Compatible license; release no older than 24 months [Assumption]; builds on the selected GHC; no unreviewed insecure FFI; for libraries affecting security (TLS, signatures)—separate review.

**13.4. Style.** `-Wall -Wcompat -Werror` for `mgw-model` and `mgw-core`; `-Wincomplete-patterns` and `-Wpartial-fields`; `StrictData` by default; effect style— `ReaderT` over `Env` with handle records. [Conclusion] This minimizes dependence on effect libraries and simplifies component substitution in tests. Template Haskell is not used in the core (build time).

## Part III. Example

### 14. Scenario A: User Response in Matrix

**Initial state.** The `general` (mesh) bridge connects Matrix, NNTP, IRC, and FTN. Message M1 from Alice has already been delivered to all networks; native identifier mappings are stored in ``native_ids``. Bob replies to M1 on Matrix.

1. **Decode (Matrix).** `EvPost` with `ThreadCtx` { `tEdges = [Edge ReplyTo (Unresolved M1) Explicit]`, `tShape = Hierarchical` }.
2. **T1.** The pair (Matrix endpoint, event ID) is new—not a duplicate; no gateway tag (author is a human). The edge is resolved to `the MsgId` of message M1. Routing excludes the source: three outbox entries are created (NNTP, IRC, FTN).
3. **NNTP.** `References` = parent’s native `Message-ID`; `Subject` — root subject prefixed with  `Re:  ;`  `From` is synthesized (`Synthesized`: author’s name, source network, address in the gateway’s domain); markup is stripped down to plain text; the gateway label is written to the header; `the Message-ID` is generated by the MGW. After `Sent` —T2.
4. **IRC.** `RelayPrefix` strategy, `Flat` format: string `<Bob> text`; with the `QuoteReply` policy—a short quote-reference to Alice. A message echoed by the server (`echo-message`) provides a native identifier for `native_ids`.
5. **FTN.** The record is accumulated according to the `Batched` policy; when the packet is formed, `MSGID`, `REPLY` (with `the` parent’s `MSGID` in FTN), and `CHRS` are added; characters outside CP866 are processed by the `Translit` policy with `LossNote`.
6. **Outbound traffic.** An NNTP entry seen during a poll matches the `native_ids` ( `outbound` direction)—blocked at L4. IRC echoes are suppressed based on an exact key and label (if no tags are present, based on the fingerprint). An FTN packet returned from a topper is filtered out based on `the MSGID`.

### 15. Scenario B: An FTN message enters other networks

1. **Decode (FTN).** The packet is read from `inbound`; the message is an echomail in the `GENERAL` domain; `CHRS` determines Unicode transcoding; `MSGID` → native identifier; `REPLY` → `Unresolved`; Subject → `tTopic`; Origin and Tearline → `ExtMap`.
2. **T1.** Deduplication by `MSGID`. If the parent is unknown based on `REPLY`, the edge is set to `Pending` status (TTL 72 hours for a batch source)—this allows future replies to be linked when the parent arrives later.
3. **Sending to real-time networks.** Waiting for the parent on the destination side is limited by a separate `parent_wait` timeout [Assumption: 60 seconds for real-time destinations, 15 minutes for batch destinations]. Once this time expires, the message is sent as an “orphan” with `a LossNote`; the connection cannot be reestablished retroactively.
4. **Identity.** Sender’s name**:** FTN → `RelayPrefix` in IRC (`<First Name Last Name [fido]>`), virtual user in Matrix (`Provisioning → Active`, name with a stable suffix), `“From”` in NNTP (non-Latin names are encoded per RFC 2047 [Not verified]).
5. **Content.** By default, the FTN body is treated as plain text; v1 does not parse simple FTN markup.

### 16. Scenario C: Full Network and Loop Suppression

Five endpoints E1…E5 are connected via a `mesh` topology. A message from E1 is delivered to E2…E5. Adapters E2…E5 see their own deliveries and must not return them to the pipeline: an exact match is triggered (`native_ids`, direction `out`), followed by a tag with `GatewayId`, then the fingerprint of the expected echo. Invariant G2 for the property test:

```latex
\forall m \;\forall e \ne \mathrm{src}(m):\quad \bigl|\mathrm{deliveries}(m,e)\bigr| = 1
```

The test generator shuffles the order of incoming events, duplicates them, and aborts the process at random points. The case of multiple gateways on a single bridge is not supported in v1: a message tagged with a foreign gateway is not routed (FR-05), which eliminates duplicates at the cost of no failover.

## Part IV. Counterexample

### 17. Threat Model and Security

| Threat | Countermeasure |
| --- | --- |
| Leakage of secrets (tokens, passwords) | `file:` and `env:` references; masking in logs; 0600 permissions on secret files; process restrictions at the systemd level [Not verified: set of parameters] |
| Impersonation | The IRC nickname (`Asserted`) is not used for authentication; the source network is always specified in the displayed name of bots |
| Content-based injections | Sanitization: removal of control characters; prohibition of CR and LF in NNTP headers; escaping of line breaks in IRC (otherwise command injection is possible); removal of the 0x01 character in FTN text (otherwise, kludge string injection is possible). Injection tests are included in the conformance suite |
| Spam amplification via the gateway | Limits on sender, endpoint, and bridge; maximum size; quarantine mode for new actors (optional); bridge pause command ` `mgwctl bridge pause`` |
| SSRF and federation abuse | Prohibition of private addresses when loading keys and objects; limits on the size and number of requests per domain; domain blocklist (section 10.5) |
| Access to the admin API | Unix socket with permissions 0600 or 127.0.0.1 with a token; public exposure is prohibited |
| Denial of service on entry | Frame, packet, and packet size limits; timeouts; limited queues; connection limits |
| Data integrity and security | SQLite backup (online backup); integrity check on startup |
| Privacy | Distribution `of EvRedact` where the purpose permits; info-level logs without message bodies; retention period (Section 11.3) |
| Supply Chain | Version locking of dependencies; audit according to the criteria in Section 13.3 |

### 18. Risk and Failure Mode Register

| ID | Risk | Measures | Residual Risk |
| --- | --- | --- | --- |
| R1 | Loops and duplicates | Three levels of deduplication, hop limit, G2 property test | Low |
| R2 | Loss of thread structure (parent did not arrive, reordering in FTN) | `Pending`, `WaitingParent`, “orphan” with `LossNote`, orphan ratio metric | Medium for batch networks |
| R3 | Name and identity collisions | Stable hash suffix, deterministic names | Low |
| R4 | Increased Abuse | Limits, quarantine, bridge suspension | Medium |
| R5 | Desynchronization of Edits and Deletions | `AsText`, `Drop`, and `LossNote` policies | Accepted (G4) |
| R6 | Encoding errors (incorrect `CHRS`, mix of CP866 and CP1251) | Region-specific configuration, `Replace` with `LossNote`, golden corpus | Medium (FTN) |
| R7 | Changes to external APIs (Matrix, ActivityPub implementations) | Adapter versioning, conformance and integration tests in CI, version locking for reference systems | Medium |
| R8 | Concurrency for writing to SQLite | Single writer, record batching, PostgreSQL backend in v2 | Low |
| R9 | Code bloat (solo development) | MVP boundary (sections 19–20), adapters strictly by phase, G1 as protection against kernel bloat | Medium |
| R10 | Duplicate entry for " `Unknown` " in transports without idempotency | Endpoint policy, `sLookup`, monitoring | Medium (IRC) |
| R11 | Queue overflow during overload | Limited queues, backpressure, depth metrics | Low |
| R12 | Multiple gateways on a single bridge | Not supported in v1; foreign labels are not routed | Accepted |

## Part V. Differences

### 19. Project Boundaries

**19.1. Core and Adapter.**

| Objective | Core | Adapter |
| --- | --- | --- |
| Framing, session, authentication, reconnection | — | Fully |
| Rate limiting | Policy and token bucket | Parsing server hints (e.g., Retry-After) |
| Thread model | `ThreadCtx`, projection, `Pending` | Encoding and decoding of native fields |
| Identity | Registry, strategies, lifecycle | Creating and Using a Native Account |
| Content Degradation | `Transformer` by `Capabilities` | Native Markup and Encoding |
| Provenance | Algorithm, Storage, Fingerprints | Tag Carrier |
| Delivery Mode | Push, poll, and batch scheduler | Declaration in `Capabilities` |
| Storage | Everything except cursors | Cursors via `CursorStore` |

**19.2. Version-Specific Features.**

| Version | Composition |
| --- | --- |
| MVP | Matrix + IRC; a single bridge with two endpoints; bidirectional text posts; one relay bot per network; SQLite durable outbox, deduplication/loop suppression, basic logs, and CLI status. No threads, no separate profiles per author, no edits/deletions/reactions, no attachments, no NNTP, FTN, or ActivityPub |
| v1.x | NNTP and FTN adapters; then threads, edits/deletions, and replay—based on MVP results |
| v2 | NNTP peer mode; FTN via message database; PostgreSQL; XMPP, Nostr, SMTP, Zulip, Mattermost; identity linking; multiple gateways per bridge; E2EE Matrix |
| Outside the project | Mailer, tosser, and transport servers; web interface (administration—CLI and API); moderation as a product |

## Part VI. Conclusion

### 20. Work Plan

| Phase | Content | Deadline | Exit Criteria |
| --- | --- | --- | --- |
| 0. Verification and Integration | For the MVP: verification of the Matrix Application Service API and IRCv3 message-tags/echo-message; selection of Synapse/Ergo and GHC versions; verification of Haskell packages; integration of SQLite/outbox and one bidirectional text; calibration of basic NFRs. Move NNTP/FTN/ActivityPub checks to their respective phases | 2 weeks | Matrix↔IRC smoke test passes; dependencies and versions are finalized; MVP risks/issues are documented; Q1–Q3 decisions are made |
| 1. Core | `mgw-model`, `mgw-adapter-api`, `mgw-store`, `mgw-core`, `mgw-adapter-mock`, `mgw-conformance`, L1–L5 rules | 4–5 weeks | L1–L5 property tests are green; G2 confirmed on mock; `kill -9` test (NFR-01) |
| 2. IRC and Matrix | Two adapters; `NativePuppet` and `RelayPrefix` mocks | 3 weeks | Bidirectional IRC and Matrix scenario in integration test; echo suppression |
| 3. Post-MVP: NNTP and FTN | Two additional adapters; hierarchical projection; encodings | After MVP, separate evaluation | Scenarios A and B (items 14–15) pass; G1 confirmed on the new adapter |
| 4. Post-MVP: ActivityPub | Inbox/outbox, signatures, and security | Following a separate evaluation | Integration with the selected server; threats in section 17 verified |
| 5. Hardening | Metrics, `mgwctl`, backup, documentation, load and chaos tests | 3 weeks | Acceptance criteria in section 21 |
| 6. v2 | Additional transport layers | As decided | — |

[Assumption] The 20–22-week estimate applies to the original expanded plan, not the scaled-down MVP. The MVP timeline should be recalculated after Phase 0 and the vertical slice of Phases 1–2.

### 21. Testing and Acceptance

**21.1. Testing Levels.** Modular; property tests for L1–L5 laws using `Event`, `ThreadCtx`, and `Capabilities` generators; golden tests for codecs on real-world data corpora (`.pkt`, NNTP articles, Matrix events, IRC strings); conformance suite; integration tests (Docker Compose with reference systems; ActivityPub—scheduled in CI); chaos tests (`kill -9`, network disconnection, database lock, queue overflow); load tests (NFR-03, NFR-04); decoder fuzzing (A3); injection tests (item 17).

**21.2. Acceptance Criteria for v1.**

| No. | Criterion |
| --- | --- |
| 1 | All requirements explicitly included within the MVP scope (section 19.2) are implemented and covered by automated tests; the remaining M-priority FRs remain on the roadmap |
| 2 | G1, G2 (on the mock network), G4, G5, and G6 are validated by measurable tests; G3 will be tested after the Thread Mapper is implemented |
| 3 | NFR-01: 1,000 iterations of ``kill -9` ` at random points in the pipeline without losing any received events |
| 4 | NFR-03 and NFR-04 have been completed on the reference configuration |
| 5 | The bidirectional Matrix↔IRC text script passes the integration test; A/B scripts are added after NNTP/FTN, and C remains a mock network test |
| 6 | There are no references to specific transports in `mgw-core` (CI check) |
| 7 | Documentation: operator’s guide, adapter contract, database schema, and migration plan |

**21.3. Definition of Done for the change.** The change is accompanied by tests; the build runs with `-Werror`; `hlint` is clean; documentation is updated; for the adapter—a green conformance suite.

### 22. Open Issues and Assumptions

| ID | Issue | Default Value |
| --- | --- | --- |
| Q1 | Project License and Dependency Compatibility (NFR-10) | Customer's Solution |
| Q2 | SQLite or PostgreSQL for v1 | SQLite |
| Q3 | MVP Composition | IRC, Matrix, NNTP, FTN; ActivityPub — Phase 4 |
| Q4 | FTN: message spool or database | Spool |
| Q5 | NNTP: client or peer mode | Client |
| Q6 | Editing and Deletion Policy (Privacy) | `EvRedact` is broadcast where the destination allows it; `cancel` is disabled in NNTP |
| Q7 | E2EE Matrix | Outside v1 |
| Q8 | Identity mapping across networks | Outside v1 |
| Q9 | Multiple gateways on a bridge | Outside v1 |
| Q10 | Numeric policies (TTL, windows, limits, thresholds) | Calibrated in Phases 0–1 |

**Register of unverified assertions** (closed in Phase 0): (1) FTN specification numbers and content, and kludge-string names; (2) INN behavior in case of duplicate `Message-IDs` and article numbering; (3) Application Service API Matrix—transaction identifier, virtual users, `m.thread`; (4) IRCv3 capabilities, client tags, string length limits; (5) ActivityPub signatures, draft-cavage, and RFC 9421; behavior of Mastodon-compatible servers; (6) NIP-10 Nostr; (7) availability and status of Haskell packages (section 13.2); (8) performance and timeline estimates (NFR, section 20).

### 23. Sources

[Unverified] All references are based on training data without verification against primary sources.

- Hohpe, G., and Woolf, B. *Enterprise Integration Patterns*. Addison-Wesley, 2003.
- Richardson, C. *Microservices Patterns*. Manning, 2018 (Transactional Outbox pattern).
- RFC 3977 (NNTP); RFC 5536 (Netnews article format); RFC 5537 (Netnews architecture); RFC 5322 (message format); RFC 2045–2047 (MIME).
- RFC 1459, RFC 2812 (IRC); IRCv3 specifications (message-tags, msgid, server-time, echo-message); Modern IRC Client Protocol.
- Matrix Specification: Client-Server API, Application Service API.
- W3C ActivityPub (2018); ActivityStreams 2.0; RFC 9421 (HTTP Message Signatures); draft-cavage-http-signatures.
- FTS-0001, FTS-0004, FTS-0009, FSP-1013 (FTN technologies; memory-based identifiers).
- Nostr NIP-10.
- RFC 9562 (UUID, including UUIDv7).