# Dual-Axis Adversarial Audit & Production Red-Line Checklist

Use this checklist during **Tier 3 (Function-Level Deep Dive)** and **Tier 4 (Modifiability & Refactoring)** of a code walk. It is specifically engineered to expose subtle defects in **AI-generated code** (which looks syntactically fluent but often lacks production invariants) and **unfamiliar legacy code** (which carries undocumented coupling and implicit assumptions).

---

## Axis 1: Semantic Truth & Ghost Abstraction Audit (AI & Legacy Smells)

AI-generated and unfamiliar code often passes superficial reading while harboring structural or semantic rot. Audit every module against these five traps:

### 1. Plausible Hallucination & Superficial Fluency
- [ ] **API Contract Reality**: Do called standard-library or third-party functions actually behave as assumed (e.g., return value semantics, nil-slice vs empty-slice behavior, thread-safety guarantees)?
- [ ] **Edge-Case Completeness**: Does the code handle zero-length inputs, 0-byte files, `nil` pointers, negative numbers, and Unicode/multi-byte paths, or did it only implement the "happy path"?
- [ ] **Business Invariant Alignment**: Does the state transition match actual domain rules, or did the author/AI invent a simplified state flow that skips required intermediate states?

### 2. Ghost Abstractions & Over-Engineering
- [ ] **Unnecessary Indirection**: Are there single-implementation interfaces, pass-through wrapper structs ("Middle Man" smell), or factory functions that add cognitive load without providing a real testing or extension seam?
- [ ] **Premature Generality**: Are there unused configuration options, generic type parameters, or hook callbacks that no caller uses? (Action: Flag for inline simplification via `/refactor`).
- [ ] **Duplicate Logic Shapes**: Did the AI generate three slightly different helper functions across files that do the same path normalization or JSON decoding?

### 3. Silent Error Swallowing & Broad Recovery
- [ ] **Ignored Errors**: Search for `_ = ...` or discarded return values on I/O, `Close()`, `Flush()`, or state persistence calls.
- [ ] **Context-Stripped Errors**: Are errors returned raw or replaced with generic strings instead of wrapping with `fmt.Errorf("context: %w", err)`?
- [ ] **Masking Fallbacks**: Does the code silently fall back to a default value when a configuration or lookup fails, hiding a broken state until much later in execution?

### 4. Implicit Coupling & Hidden State
- [ ] **Temporal Coupling**: Must Function A always be called before Function B without compile-time or runtime enforcement?
- [ ] **Global / Package-Level State**: Does the function mutate package-level variables, singletons, or environment variables that break parallel test execution?
- [ ] **Side-Effecting Getters**: Does a function named `Get*`, `Find*`, or `Check*` secretly mutate state, write files, or spawn background goroutines?

---

## Axis 2: The 5 Production Red Lines & 6-Gate Inspection

Every critical-path function must be audited against the five hard production red lines and six execution gates.

### Red Line 1: Lifecycle & Timeout Propagation
- [ ] **Context Propagation**: Does every blocking I/O, DB query, HTTP request, and subprocess execution accept and respect `context.Context`?
- [ ] **Explicit Deadlines**: Are `http.Client`, `http.Server` (`ReadHeaderTimeout`, `WriteTimeout`, `IdleTimeout`), and RPC clients configured with explicit non-zero timeouts?
- [ ] **Timer/Ticker Cleanup**: Is every `time.NewTicker` or child context paired with `defer ticker.Stop()` or `defer cancel()` on all return paths?

### Red Line 2: Lock Discipline & Concurrency Safety
- [ ] **Minimal Critical Sections**: Mutex (`sync.Mutex` / `sync.RWMutex`) must protect *only* in-memory state reads/mutations. **Never hold a lock across:**
  - Disk I/O, filesystem walking, or `os.Stat` calls.
  - Network requests or HTTP/RPC calls.
  - Subprocess execution (`exec.Command`).
- [ ] **Snapshot-Then-Process Pattern**: Copy pointers/slices under `RLock()`, release the lock immediately, and perform heavy processing outside the lock.
- [ ] **Lock Order & Deadlock Freedom**: When multiple locks exist, document and verify a strict global acquisition order. Ensure no recursive `RLock()` calls occur in Go (which deadlock if a concurrent `Lock()` is waiting).
- [ ] **Bounded Goroutines**: Every spawned goroutine must have a clear exit condition, panic safety (where appropriate), and concurrency bounding (worker pool / semaphore / `errgroup.SetLimit`).

### Red Line 3: Memory & Flow-Control Caps (DoS Hardening)
- [ ] **Request Body Caps**: Enforce `http.MaxBytesReader` (e.g., 1MB cap) before `json.NewDecoder` or `io.ReadAll` on untrusted or proxied HTTP bodies.
- [ ] **Unbounded Collection Growth**: Are in-memory maps, caches, or slices bounded by max-entry limits or TTL eviction?
- [ ] **Streaming vs Buffering**: For large file lists or data transfers, does the code stream line-by-line (`bufio.Scanner` / `io.Reader`) instead of loading multi-gigabyte payloads into memory?

### Red Line 4: State Consistency, CAS Loops & Failure Atomicity
- [ ] **Optimistic Concurrency (CAS)**: Are concurrent state updates protected by Compare-And-Swap version checks or atomic state transitions with bounded backoff retry?
- [ ] **No Infinite Retry Loops**: Every retry loop must have a hard `maxRetries` cap, context cancellation check, and jittered backoff.
- [ ] **Failure Atomicity (Zero Partial State)**: If step 3 of a 4-step operation fails, are steps 1 and 2 rolled back or cleaned up so the system never rests in an orphaned/corrupted state?
- [ ] **Idempotency**: Can a failed or timed-out request be safely retried by the caller without duplicating jobs or corrupting data?

### Red Line 5: Boundary Containment & Anti-Injection
- [ ] **Fail-Fast Gate Ordering**: Are checks ordered from cheapest to most expensive?
  `HTTP Method ➔ Auth Token ➔ MaxBytesReader ➔ JSON Syntax ➔ Path Canonicalization ➔ Store/Disk Lookup`
- [ ] **Path Traversal Containment**:
  - Canonicalize paths via `filepath.Clean` / `path.Clean`.
  - Enforce trailing slash boundary on prefix checks: `strings.HasPrefix(cleanTarget, cleanRoot + "/")` (prevents `/data/app-evil` matching root `/data/app`).
  - Verify symlink resolution (`filepath.EvalSymlinks`) where untrusted symlinks could escape mount roots.
- [ ] **Command Injection Immunity**: Pass arguments as discrete slice elements to `exec.CommandContext(ctx, bin, arg1, arg2)`; never interpolate user input into `sh -c`.
- [ ] **Observability & Audit Trail**: Log security-critical actions with actor identity, remote address, target resource, latency, and distinct machine-parseable error codes (never leak internal stack traces or tokens to clients).
