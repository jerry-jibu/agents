---
name: code-walk
description: 'Conduct an exhaustive 4-tier, function-level code walk and adversarial review for unfamiliar codebases or AI-generated code. Use whenever the user asks for "code walk", "代码走读", "deep dive", "函数级走读", "源码剖析", "walk through the code", "review AI code", "理解陌生代码", or asks to deeply inspect architecture, component boundaries, data/control flows, lock discipline, anti-injection boundaries, and modifiability/blast radius. Produces progressive dual-artifacts: a Git-friendly Markdown guide and a zero-dependency interactive HTML presentation (Document/Slideshow views, Archify topology, and verification quizzes).'
depends-on: archify, diagram-design
---

# Code Walk 2.0 — 4-Tier Deep Dive & Modifiability Engine

Transform unfamiliar legacy modules or AI-generated code into deeply understood, safely modifiable, and production-hardened systems. Every code walk reconstructs the mental model across **four progressive tiers** and audits code along **two adversarial axes**.

---

## The 4-Tier Comprehension Model

```
Tier 1: Architecture & Components ──▶ Tier 2: Data & Control Flow ──▶ Tier 3: Critical Function Deep Dive ──▶ Tier 4: Modifiability & Blast Radius
```

1. **Tier 1 — Architecture & Component Boundaries**: C4 Container/Component topology, process boundaries, ports, protocols, and trust perimeters.
2. **Tier 2 — Key Data Flow & Control Flow**: End-to-end request/event lifecycle ("Tracer Bullet") and explicit state machine transitions (including failure rollback paths).
3. **Tier 3 — Critical Path Function-Level Deep Dive**: Line-by-line dissection of critical functions across 4 categories, pinned with contracts (`Preconditions`, `Postconditions`, `Invariants`, `Blast Radius`), while summarizing routine helper functions as compact contract tables.
4. **Tier 4 — Modifiability & Blast Radius Playbook**: Realistic change scenario deductions, architectural seams vs. rigid spots, a function-level Blast Radius Matrix, and a 5-Step Safe Modification Playbook.

---

## Execution Workflow

### Step 1: End-to-End Topological Trace (Tier 1 & Tier 2)

Never stop at the client, CLI, or proxy layer. Trace the full execution wire down to persistence and external daemons:

1. **Pin Entry & Exit Points**: Trace CLI flags / HTTP routes / RPC handlers ➔ middleware & auth gates ➔ reverse proxy / loopback routing ➔ core service handlers ➔ storage / external daemons.
2. **Map State & Control Flow**: Extract the state machine (states, guards, mutating functions, and error rollback paths).
3. **Generate Architecture Visual**: Invoke `/archify` or `/diagram-design` to produce a validated standalone SVG/HTML topology diagram when multi-component interactions are involved.
   - *Completion Criterion*: Every hop from ingress to storage is mapped with exact file paths, ports, and protocol contracts.

### Step 2: Critical Function Classification & Dissection (Tier 3)

Avoid information sprawl by classifying functions before dissecting:

1. **Select Critical-Path Functions** across four high-risk categories:
   - **State & CAS Loops**: Functions mutating state machines, stores, or executing Compare-And-Swap retries.
   - **Boundary & Protocol Adaptation**: HTTP/RPC handlers, dual-mount path resolvers, subprocess executors.
   - **Lock & Concurrency Control**: Functions acquiring mutexes, spawning goroutines, or managing channels/streams.
   - **Core Domain Algorithms**: Security gates, file scanners, scheduling, or sharding algorithms.
2. **Document the 4-Pillar Contract** for every critical function:
   - `Preconditions`: Required caller state, auth assumptions, and lock holding rules.
   - `Postconditions`: Guaranteed return state, persistence guarantees, and cleanup.
   - `Maintained Invariants`: System-wide truths that must hold before and after execution.
   - `Blast Radius`: Upstream callers and downstream components impacted if this function's signature or semantics change.
3. **Compact Helper Summary**: Group trivial getters, DTO mappers, and glue functions into a single contract summary table.
   - *Completion Criterion*: Every critical function has a complete 4-pillar contract and line-range link (`file:///...#L10-L50`).

### Step 3: Dual-Axis Adversarial Audit (AI & Legacy Code Review)

Load and apply [`references/inspection-checklist.md`](references/inspection-checklist.md) to every critical function:

- **Axis 1 — Semantic Truth & Ghost Abstraction Audit**:
  - Hunt for AI code smells: plausible hallucinations (misused APIs, unverified happy-path assumptions), ghost abstractions (single-use interfaces, pointless wrappers), silent error swallowing (`_ = ...`), and hidden temporal coupling.
- **Axis 2 — The 5 Production Red Lines**:
  1. *Lifecycle & Timeouts*: `context.Context` propagation, client/server timeouts, ticker cleanup.
  2. *Lock Discipline*: Zero I/O or network calls inside mutex critical sections; snapshot-then-process pattern; deadlock freedom.
  3. *Memory & Flow Caps*: `http.MaxBytesReader` on request bodies, bounded slices/maps, streaming over full-buffering.
  4. *State Consistency & CAS*: Bounded CAS retry loops with backoff, failure atomicity (zero partial/orphaned state), 0-byte edge-case bypass.
  5. *Boundary Anti-Injection*: Fail-fast gate ordering, `filepath.Clean` + trailing slash boundary check, array-based `exec.CommandContext`.
  - *Completion Criterion*: All 5 red lines and AI smell traps are audited; concrete refactoring items are recorded for `/refactor`.

### Step 4: Modifiability & Blast Radius Engineering (Tier 4)

Ensure the reader can safely modify and maintain the code:

1. **Deduce 2–3 Realistic Change Scenarios**: Trace exact touchpoints and at-risk invariants for likely future features (e.g., adding a filter flag, swapping storage backends, scaling concurrency).
2. **Map Seams vs. Rigid Spots**: Highlight clean extension points (interfaces/hooks) versus fragile hardcoded areas (shotgun surgery risks).
3. **Build the Blast Radius Matrix & 5-Step Safe Modification Playbook**: Specify exact regression test commands required when modifying each core function.

### Step 5: Progressive Dual-Artifact Delivery & Live Test Grounding

Deliver two synchronized artifacts in `docs/code-walk/` (or the user's specified docs directory):

1. **Git-Friendly Markdown Guide** (`000X-<topic>-codewalk.md`):
   - Follow [`references/modifiability-playbook-template.md`](references/modifiability-playbook-template.md).
   - Optimized for Git diffs, PR reviews, and future AI context loading.
2. **Zero-Dependency Interactive HTML Deck** (`000X-<topic>-codewalk.html`):
   - Base on [`assets/template-codewalk.html`](assets/template-codewalk.html).
   - Includes **Document View** (with sticky 4-Tier navigation bar), **Slideshow View** (`[j]`/`[k]`/`[Space]` keyboard navigation), function contract cards, Blast Radius Matrix, and **Active Verification Quizzes**.
3. **Live Test Grounding**:
   - Run the module's automated test suite (`go test -v`, `pytest`, `npm test`) to verify claims and confirm test commands in the Blast Radius Matrix work out-of-the-box.

---

## Bundled References & Assets

- [`references/inspection-checklist.md`](references/inspection-checklist.md) — Dual-Axis Adversarial Audit (AI Smells & 5 Production Red Lines). Read during Step 3.
- [`references/modifiability-playbook-template.md`](references/modifiability-playbook-template.md) — Markdown blueprint for the 4-Tier guide, Blast Radius Matrix, and Safe Modification Playbook. Read during Step 4 & Step 5.
- [`assets/template-codewalk.html`](assets/template-codewalk.html) — Self-contained 4-Tier interactive HTML template (Document + Slideshow + Quiz). Read during Step 5.
