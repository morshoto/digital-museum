# AGENTS.md


## 1. Mission


This repository is a peer-to-peer marketplace application with an AI agent backend.
The backend exposes a Hono API backed by a Google ADK multi-agent pipeline (supervisor → specialist agents) that handles user queries about listings and policy validation. For detailed design decisions, refer to the relevant documentation, especially `docs/adr/`.


## 2. Project Map


- `backend/` - Hono API server (Node.js + TypeScript)
 - `src/` - Layered application source; see `backend/src/README.md` for the full directory map
   - `routes/` - HTTP handlers (validation → service → response)
   - `service/` - Use cases; `service/agent/` runs the ADK multi-agent pipeline
   - `client/` - External service adapters (`openai.llm.ts` bridges ADK to the OpenAI-compatible gateway)
   - `domain/` - Prisma DB client and pure business-rule functions
   - `schema/` - Zod schemas and inferred types
   - `config/` - Env vars, CORS, logger, prompt loader
 - `data/prompt/` - Agent prompt files (`supervisor.md`, `info.md`, `policy_validator.md`)
 - `tests/` - All tests: `tests/unit/` (mirrors the `src/` layout), `tests/e2e/`, and integration tests
 - `prisma/` - Prisma schema and migrations
- `docs/` - Design documents such as the PRD and SDD
- `context` - Local docs context CLI for chunking and retrieval from `docs/`, `android/docs/`, and `backend/docs/`
- `scripts/` - Supporting scripts


## 3. Working Rules


- Read this file before making code, docs, or test changes.
- Read the relevant code and nearby tests before making changes.
- Use `node scripts/context.mjs build` and `node scripts/context.mjs search "<query>"` when you need repo docs context before editing; prefer the indexed docs roots over ad hoc manual scanning.
- Check `docs/PRD.md` and `docs/SDD.md` before changing design-related decisions.
- Check `docs/adr/` before changing architecture decisions.
- Keep the change scope as small as possible.
- Do not over-scope implementation fixes, refactors, or test additions unless the design decision changes.
- Keep logic files light: put durable knowledge in markdown docs, not in long explanatory comments — see §7.
- Run tests, type checks, and lint when feasible.


## 4. Decision Index


The current starting points for major decisions are:


- Product requirements: `docs/PRD.md`
- System design: `docs/SDD.md`
- Architecture decisions: `docs/adr/`
- ADR wiki site: `wiki/README.md`


If a decision is not covered here, add or update an ADR before changing the design.


## 5. Change Policy


**Feature Update**


The following changes are likely to update design decisions, so consider updating the documentation separately:


- adding or changing user-facing screens, navigation flows, or entry points
- adding or removing major dependencies
- changing module boundaries
- changing persistence, schema, or migration strategy
- changing security, authentication, authorization, or privacy behavior
- adding long-lived conventions that future contributors must follow
- introducing a new architectural pattern or repo-wide convention


If one of the items above applies, **create or update an ADR** before changing the design, and update the relevant product docs (`docs/PRD.md`, `docs/SDD.md`, or screen-design docs) when the user-visible flow changes.


When in doubt, assume user-visible navigation or startup behavior needs a docs update and verify the current source of truth before committing the code.


**Bug Fix**


The following changes usually do not require an ADR update:


- bug fixes
- local refactors
- test additions
- formatting changes
- copy or wording adjustments
- implementation details that do not affect future decisions


Exception: if a bug fix or implementation task surfaces a non-obvious fact (a provider quirk, an infra gotcha, a protocol/schema detail), record it in the relevant markdown doc as part of that change. This needs no ADR, but it is the expected home for that knowledge — see §7. It does not count as over-scoping.


## 6. Investigation Order


When making a non-trivial change, investigate in this order:


1. Read the relevant code.
2. Check `docs/PRD.md` and `docs/SDD.md`.
3. Check `**/docs/adr/` for related decisions.
4. Check nearby tests and responsibility boundaries.
5. Make the smallest coherent change.
6. Add or update tests as needed.
7. Update or add an ADR only if the decision changes future work.


## 7. Documentation & Comments


Keep logic files as light as possible. Durable knowledge belongs in markdown docs, not in long inline prose — heavy comments duplicate docs, drift out of date, and bury the code.


Every comment is one of three things; treat anything else as a smell:


1. **Durable knowledge** — provider quirks, infra gotchas, protocol/schema facts, auth models, design rationale. → Write it in markdown and leave a pointer. Homes: `docs/`, `backend/docs/`, or the deciding ADR (a quirk that follows from a recorded decision goes in that ADR as an "Implementation notes" section). The `docs-over-comments` skill keeps a per-subsystem homes table.
2. **Point-of-code gotcha** — a foot-gun at that exact line (e.g. forcing TLS on a pool). → Keep it, one or two lines.
3. **Narration / history** — restates the next line, debugging post-mortems, "why my change is correct". → Delete; git history is the record.


Pointer rules:


- **One pointer per file, in the header, is the default budget.** Name the doc path and the section (`// Contract + rationale: backend/docs/api/README.md (GET /ready)`). The reference convention is `src/client/*.ts`. A `(doc §N)` breadcrumb on every function is noise — shrinking comment blocks while multiplying pointers leaves the file just as heavy.
- **Link, don't restate.** Point at the doc instead of narrating the fact again, and never point at a doc path you haven't verified exists.
- **Fix stale facts while you're there.** When writing a fact into a doc (or keeping a labeled comment), check the surrounding statements against the code — a pointer into a doc that says the wrong thing is worse than the prose it replaced.
- **Documenting a discovered fact is in scope** for the change that found it (see §5, Bug Fix exception) — no ADR required, but update the doc.


For sweeping an over-commented file use the `/docs-over-comments` skill; for decomposing a monolithic module use `/split-module` (`.claude/skills/`).

