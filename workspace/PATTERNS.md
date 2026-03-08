# Vultisig — Cross-Repo Coding Patterns

Patterns that apply across all Vultisig repos. Repo-specific patterns are
in each repo's CLAUDE.md.

## Commit Messages

Conventional commits, always referencing the issue:

```
fix: correct TRC20 fee calculation (#42)
feat: add Solana SPL token support (#108)
refactor: extract chain config to shared module (#95)
docs: update keysign flow diagram (#67)
test: add reshare edge case coverage (#83)
```

First line: imperative mood, <72 characters, issue number in parens.
No body needed for small changes. Add body for context on larger changes.

## Branch Naming

```
agent/{issue-number}-{slug}
```

Examples:
- `agent/42-fix-trc20-fee`
- `agent/108-add-solana-spl`

Slug: lowercase, hyphens, max 50 chars. Derived from issue title.

## Error Handling

**Go repos:**
- Wrap errors with context: `fmt.Errorf("signing tx: %w", err)`
- Use `errors.Is` / `errors.As` for matching
- Never panic across API boundaries

**TypeScript repos:**
- Custom error classes with error codes
- Validate external data at boundaries (Zod/Valibot)
- Never swallow errors silently

## Testing

- Run existing tests FIRST to establish baseline
- If tests fail before your changes → note in PR, don't fix unrelated tests
- Add tests for new behavior
- Test edge cases: empty input, nil/undefined, boundary values
- For crypto code: test with known test vectors

## PR Description

Always follow the repo's PR template. Key elements:
- `Fixes #{issue-number}` (auto-closes issue)
- Summary of WHAT changed and WHY
- Agent metadata (auto-filled)
- Test plan with checkboxes

## State Management

**React (Windows app):**
- Zustand for global state
- React Query for server state
- Local state for UI-only concerns

**iOS (Swift):**
- @Observable + MVVM
- @MainActor for ViewModels

**Android (Kotlin):**
- Jetpack Compose + MVVM
- Coroutines for async

## Import Paths

**TypeScript monorepos:**
- Use workspace package imports, not relative paths across packages
- Relative paths within a package are fine
- No barrel files in applications

**Go:**
- Use `internal/` for access control
- Avoid `util`, `common`, `helpers` packages
