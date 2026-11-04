# Structured Code Walk & Modifiability Guide Template

Use this structure when generating the permanent Git-tracked Markdown companion (`docs/code-walk/000X-<topic>-codewalk.md`). Every section must use clickable `file:///...#L10-L20` links for files, types, and functions.

---

```markdown
# [000X] <Module / Feature Name> — Deep Dive Code Walk & Modifiability Guide

- **Scope**: `<packages / directories covered>`
- **Interactive Companion**: [`000X-<topic>-codewalk.html`](./000X-<topic>-codewalk.html)
- **Architecture Diagram**: [`<diagram>.html`](../reference/<diagram>.html)

---

## Tier 1: Architecture & Component Boundaries

### 1.1 System Context & Component Topology
<!-- Describe C4 Container/Component boundaries, daemon processes, and how this module fits into the larger system. -->

### 1.2 Trust Boundaries, Ports & Contracts
| Component / Process | Listen / Endpoint | Protocol & Auth | Upstream Caller | Downstream Dependency | Trust Level |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `<e.g. recall-proxy>` | `<0.0.0.0:8090>` | `<HTTP Bearer>` | `<archive-cli>` | `<jibuarchival :58080>` | `<Untrusted Edge>` |

---

## Tier 2: Key Data Flow & Control Flow

### 2.1 End-to-End Request Lifecycle (Tracer Bullet)
<!-- Trace the exact sequence from ingress to persistence/egress across process/module boundaries. -->

### 2.2 Core State Machine & Transitions
| Current State | Trigger / Event | Guard Condition | Next State | Mutating Function | Failure / Rollback Path |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `<e.g. Pending>` | `<ApplyRequest>` | `<Files > 0>` | `<Running>` | [`HandleApply`](file:///...) | `<Revert to Idle>` |

---

## Tier 3: Critical Path Function-Level Deep Dive

### 3.1 Critical Function Classification
Classify all inspected functions into the 4 core categories:
1. **State Transitions & CAS Loops**
2. **Boundary & Protocol Adaptation**
3. **Lock Discipline & Concurrency Control**
4. **Core Domain Validation & Algorithms**

### 3.2 Function Dissection Cards

#### [`FunctionName`](file:///absolute/path/to/file.go#L10-L50)
- **Category**: `<State/CAS | Boundary | Lock/Concurrency | Core Domain>`
- **Preconditions**: `<What must be true before calling (e.g., Auth verified, lock NOT held)>`
- **Postconditions**: `<What is guaranteed upon return (e.g., Store persisted atomically, response written)>`
- **Maintained Invariants**: `<System rules preserved (e.g., Target path strictly inside source root)>`
- **Concurrency & Lock Discipline**: `<Locks acquired, critical section scope, I/O isolation>`
- **Dual-Axis Audit Findings**:
  - *Semantic / AI Smell Check*: `<Pass or specific finding>`
  - *Production Red-Line Check*: `<Gates & Red Lines verified>`

### 3.3 Helper & Glue Functions Contract Summary
| Function | Location | Role & Contract | Side Effects |
| :--- | :--- | :--- | :--- |
| [`helperFn`](file:///...) | `file.go:L100` | `<1-line contract summary>` | `<None / Mutates X>` |

---

## Tier 4: Modifiability, Blast Radius & Safe Maintenance Playbook

### 4.1 Realistic Evolution & Change Scenarios
Walk through 2–3 high-probability future requirements and exact code touchpoints:
- **Scenario A: `<e.g., Adding a new filter parameter or CLI flag>`**
  - *Touchpoints*: `[file1.go](file:///...)` ➔ `[file2.go](file:///...)`
  - *Invariants at Risk*: `<What could break if done naively>`
- **Scenario B: `<e.g., Changing storage format or concurrency limit>`**
  - *Touchpoints*: `...`
  - *Invariants at Risk*: `...`

### 4.2 Architectural Seams vs. Rigid Spots
- **Clean Extension Points (Seams)**: `<Interfaces, strategy hooks, or config structs where changes drop in cleanly>`
- **Rigid / Coupled Spots (Watch Out)**: `<Hardcoded constants, switch cascades, or shared structs requiring multi-file edits>`

### 4.3 Core Function Blast Radius Matrix
| Modified Function / Struct | Direct Upstream Callers | Downstream Side Effects | Broken Invariants if Misconfigured | Required Regression Tests |
| :--- | :--- | :--- | :--- | :--- |
| [`FunctionName`](file:///...) | `<Callers>` | `<DB / Disk / RPC impact>` | `<e.g. Lock inversion / Path escape>` | `go test -v ./pkg/... -run TestX` |

### 4.4 5-Step Safe Modification Playbook
1. **Step 1 — Pin Contract & Tests**: Run existing baseline tests (`<exact command>`) and write a failing test for the new behavior.
2. **Step 2 — Respect Gate & Lock Order**: Insert new validations *before* lock acquisition or disk I/O.
3. **Step 3 — Update Wire & Domain Types**: Modify request/response DTOs and ensure backward-compatible JSON tags.
4. **Step 4 — Verify CAS & Failure Cleanup**: Ensure any new state mutation participates in atomic rollback on error.
5. **Step 5 — Run Boundary & Concurrency Verification**: Execute `go test -race ./...` and verify edge cases (0-byte, timeout, unauthorized).

### 4.5 Adversarial Audit Findings & Refactoring Debt
| Severity | Category (AI Smell / Red Line) | Location | Issue Description | Recommended Fix (`/refactor`) |
| :--- | :--- | :--- | :--- | :--- |
| `<High/Med/Low>` | `<e.g. Ghost Abstraction / Lock>` | [`file.go#L45`](file:///...) | `<Description>` | `<Concrete refactoring action>` |
```
