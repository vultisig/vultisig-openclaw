# Coding Standards — Vultisig Dev Agent

_Agent's coding DNA. Each developer can customize this file._

---

## Engineering Values

- **Concise > verbose** — every line earns its place
- **Readable > clever** — future-you will thank present-you
- **Explicit > implicit** — no magic, no surprises
- **Simple > complex** — three similar lines beat a premature abstraction

## Writing Rules

1. **Methods < 15 lines** — beyond this, Extract Method
2. **Classes < 200 lines** — beyond this, Extract Class
3. **Parameters <= 3** — beyond this, Introduce Parameter Object
4. **Nesting <= 2 levels** — beyond this, Guard Clauses
5. **No magic numbers** — use named constants
6. **Self-documenting names > comments** — rename before commenting

## Smell Detection

| You See | You Do |
|---------|--------|
| Long method | Extract Method |
| Large class | Extract Class |
| Duplicate code | Extract Method → Pull Up |
| Long parameter list | Introduce Parameter Object |
| Switch on type | Replace with Polymorphism |
| Nested conditionals | Guard Clauses (early returns) |
| Magic numbers | Named Constants |
| Dead code | Delete it |

## Refactoring Discipline

1. **Test first** — never refactor without a safety net
2. **One thing at a time** — never mix refactoring with features
3. **Small steps** — verify tests pass after each change
4. **Separate commits** — refactoring commits vs feature commits

---

## TypeScript Rules

- Default to `type` over `interface`. Use `interface` only for `extends` or class contracts.
- Never use `any` without a comment. Prefer `unknown` and narrow.
- Model states with discriminated unions.
- Use `as const` objects instead of enums.
- Validate external data at boundaries with Zod or Valibot.
- No barrel files in applications.
- Annotate function signatures (params + return). Let inference handle bodies.

### React (vultisig-windows)
- Never store server data in client state — use TanStack Query.
- Derive state during render, not `useEffect` + `setState`.
- One responsibility per component.
- Test behavior, not implementation (React Testing Library).

## Go Rules

- Follow `go.dev/doc/modules/layout`. Lowercase single-word package names.
- `internal/` for access control. Avoid `util`, `common`, `helpers`.
- Wrap errors with context: `fmt.Errorf("reading config %s: %w", path, err)`.
- Use `errors.Is` / `errors.As` for matching. Never type-assert errors.
- Never panic across API boundaries. `Must*` prefix only at init time.
- `context.Context` as first parameter. Never store in structs.
- Always run tests with `-race`.
- Table-driven tests for non-trivial functions.
- `gofmt` + `golangci-lint` (staticcheck, govet, errcheck, gosec, revive).

## Swift Rules

- Default to structs. Classes only for reference semantics.
- `guard let` for early exit. No force unwrapping (`!`) except in tests.
- async/await with structured concurrency. GCD is legacy.
- `@Observable` (iOS 17+) over `ObservableObject` + `@Published`.
- `@MainActor` for ViewModels. `nonisolated` for non-UI methods.
- MVVM as default.

## Kotlin Rules

- Sealed classes for state and event modeling.
- Coroutines for async. No blocking calls on main thread.
- Jetpack Compose + MVVM.
- No force unwrap (`!!`) — use safe calls or `requireNotNull` with clear message.

---

## Security Defaults

**ALWAYS:**
1. Parameterized queries only
2. Input validation on ALL entry points
3. Output encoding for user-facing content
4. Auth checks BEFORE data access

**NEVER:**
- `eval()`, `exec()`, or dynamic code execution
- Hardcoded secrets
- Disabled SSL/TLS verification
- Logging sensitive data (keys, tokens, passwords)

## Dependency Security

- **NEVER** add dependencies without explicit approval
- Verify package names exist on the registry before installing
- Pin exact versions in lock files
- Run `npm audit` / `yarn audit` / `go mod verify` before merging dependency changes

---

## Post-Write Review

Always review your own code when done:
- Trim unnecessary lines
- Simplify expressions
- Remove boilerplate that adds nothing
- Could this be simpler? If yes, make it simpler
