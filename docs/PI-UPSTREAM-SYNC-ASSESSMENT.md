# Pi upstream sync assessment: what a real sync would touch

Status: assessment only, no sync performed. This persists the file-level
detail behind the aggregate numbers already in `UPSTREAMS.md` ("no sync has
been performed yet") and the effort conclusion from the earlier informal
analysis (never previously written down) that led to keeping
`@earendil-works/pi-*` as `devDependencies` instead of attempting a real
sync.

Re-measured 2026-09-06 against the live `earendil-works/pi` tag `v0.85.0`
(dated 2026-09-04, still the latest tag as of this writing — no newer
release since). Re-run before acting on this if time has passed:

```bash
git remote add upstream-pi https://github.com/earendil-works/pi.git   # if not already present
git fetch upstream-pi tag v0.85.0
git diff --stat HEAD v0.85.0 -- packages/tui packages/ai packages/agent
git diff --name-status HEAD v0.85.0 -- packages/tui packages/ai packages/agent
```

## Aggregate

**699 files changed, +129,430 / −48,564 lines** across `packages/tui`,
`packages/ai`, `packages/agent` (our vendored `pi-tui`/`pi-ai`/`pi-agent-core`
forks vs upstream `v0.85.0`).

By git status:

| status | count | meaning |
|---|---|---|
| `A` (added upstream) | 475 | files that exist in `v0.85.0` but not in our fork at all |
| `M` (modified) | 165 | files present in both, content has diverged |
| `D` (deleted upstream) | 52 | files present in our fork, absent from `v0.85.0` (mostly superseded by renames below) |
| `R` (renamed) | 7 | see below |

## The big one: an entirely new subsystem we don't have

**82 of the 475 upstream-only files are under `packages/agent/src/harness/`**
— a subsystem that does not exist in our fork in any form:
`harness/agent-harness.ts`, `harness/context.ts`, `harness/messages.ts`,
`harness/result.ts`, `harness/skills.ts`, `harness/system-prompt.ts`,
`harness/prompt-templates.ts`, `harness/runtime/reducer.ts`,
`harness/session/`, `harness/tools/`, `harness/utils/`, plus a new
`search/` module and top-level `stream-fn.ts`/`node.ts`. `pi-agent-core`'s
own `src/index.ts` now re-exports all of it. This is pi.dev's own
"continual harness" concept — evolved independently of (and differently
from) Prime Agent's own harness/refinement system that our fork already
has under `packages/coding-agent/src/core/refinement/`. **A real sync
would mean deciding whether to adopt pi's harness model, keep our own, or
run both** — this is a design decision, not a mechanical merge.

Other upstream-only concentrations (lower risk, mostly additive):
`packages/ai/src` (147 new files — see the OAuth reorg below for the part
that matters), `packages/agent/test`/`packages/ai/test` (132 new test
files, upstream's own coverage growth), `packages/agent/docs` (53 new
doc files), `packages/tui/native` (10 new files, unclear purpose without
reading them), `packages/agent/benchmark` (11 new files, a benchmark
harness we don't have).

## A directory move that directly hits code we've customized

Upstream renamed `packages/ai/src/utils/oauth/` → `packages/ai/src/auth/oauth/`
and added several new providers in the new location:

| our fork (`utils/oauth/`) | upstream `v0.85.0` (`auth/oauth/`) |
|---|---|
| `anthropic.ts`, `github-copilot.ts`, `oauth-page.ts`, `openai-codex.ts`, `pkce.ts`, `types.ts`, `index.ts` | same six, plus **new**: `device-code.ts`, `kimi-coding.ts`, `load.ts`, `openrouter.ts`, `radius.ts`, `xai.ts` |

**This is the exact directory we hand-edited for ACRYL branding**
(`oauth-page.ts`'s inline SVG/`aria-label`/page titles, per commit
`b150ea3e`/the later ACRYL rename). A real sync would need to: (1) take the
directory move, (2) take the new provider files, (3) **re-apply our
branding patch on top of upstream's rewritten `oauth-page.ts`**, not just
overwrite it — check whether upstream's version still uses the same
`renderPage()`/`oauthSuccessHtml()`/`oauthErrorHtml()` shape before assuming
a clean patch applies. Related renames in the same family:
`packages/ai/src/providers/{github-copilot-headers,google-shared,openai-codex-responses,transform-messages}.ts`
→ `packages/ai/src/api/...` (the general provider-file reorg), and
`packages/ai/test/anthropic-opus-4-7-smoke.test.ts` →
`anthropic-opus-4-8-smoke.test.ts` (upstream bumped their smoke-test model).

## Top-churn shared (modified) files, ranked

Excluding the two generated/reference files that dominate by line count but
carry low real-conflict risk (`packages/ai/src/models.generated.ts`,
+22,938/−0: purely additive catalog growth, regenerate rather than merge;
`packages/ai/scripts/generate-models.ts`, 3,078 lines changed: the
generator itself, worth a real look but isolated), the highest-churn
**hand-maintained logic files** are:

```text
packages/tui/src/tui.ts                       1,956 lines changed
packages/tui/src/latex.ts                     1,658
packages/ai/src/providers/anthropic.ts        1,305
packages/tui/src/components/editor.ts         1,037
packages/ai/src/providers/amazon-bedrock.ts   1,033
packages/ai/src/models.ts                       940
packages/agent/src/agent-loop.ts                702
packages/ai/src/providers/mistral.ts            647
packages/tui/src/components/markdown.ts         640
packages/ai/src/providers/google-vertex.ts      629
packages/tui/src/utils.ts                       561
packages/ai/src/types.ts                        530
packages/tui/src/terminal.ts                    507
packages/ai/src/providers/google.ts             477
```

These 14 files are where a real sync's actual merge conflicts would
concentrate — each is a core piece (TUI render loop, markdown/latex
rendering, the editor component, every major provider adapter, the agent
loop itself, shared type definitions).

## Public export surface: no confirmed breaking removals

Diffed each package's `src/index.ts` between our fork and `v0.85.0`
directly. Every line that appears to be "removed" is a `.js` → `.ts`
import-extension rewrite of the *same* export (e.g.
`export { Editor, ... } from "./components/editor.js"` in our fork vs
`.../editor.ts` upstream) — a module-resolution convention difference
between the two TypeScript configs, not a real symbol removed. **No export
that our fork's `packages/coding-agent` actually imports was confirmed
missing or renamed** at this top-level surface. This does not rule out
signature-level changes *inside* the 14 high-churn files above — only
that nothing disappeared from the public API list.

## Effort conclusion (unchanged from the earlier informal analysis, now backed by real numbers)

Given 82 net-new files in an unfamiliar subsystem, 14 core files with
500-2,000 lines of real churn each, a directory reorg hitting code we've
already hand-patched, and no established process for validating a
harness-model decision either way: a genuine sync is **not a mechanical
merge**. Estimated at **15-30 dev-days** for the initial sync plus
**0.5-2 dev-days per subsequent weekly upstream release** to stay current,
consistent with the earlier estimate.

**Current mitigation remains sufficient**: `@earendil-works/pi-*` live in
`packages/coding-agent/package.json`'s `devDependencies`, not
`dependencies` — the published CLI's bundled build (`dist/bundle/cli.js`)
inlines these packages from our local workspace fork at build time and
never needs them resolvable as real npm dependencies for consumers. Local
development still gets the vendored fork via workspace symlinks. No sync
is required for the CLI to keep working; a sync is only needed if we
decide we want pi.dev's post-fork improvements (the harness subsystem,
new OAuth providers, provider-file fixes in the 14 high-churn files, the
`auth/oauth` reorg) badly enough to spend the 15-30 days plus ongoing
maintenance.

## If a sync is ever greenlit

Suggested order, cheapest/lowest-risk first:

1. Pull the additive, low-conflict pieces first: new OAuth providers
   (`device-code.ts`, `kimi-coding.ts`, `openrouter.ts`, `radius.ts`,
   `xai.ts`) and new test files — these don't touch anything we've
   customized.
2. Do the `utils/oauth/` → `auth/oauth/` move and the `providers/` →
   `api/` reorg as a dedicated commit, re-applying the ACRYL branding
   patch to `oauth-page.ts` immediately after, verified against the
   live OAuth flow the same way `oauth-page.ts`'s original rebrand was
   verified (browser test through Chrome, not just a visual diff).
3. Take the 14 high-churn hand-maintained files one at a time, diffing
   each against `git diff HEAD v0.85.0 -- <file>` individually rather
   than as part of the bulk sync, since these are exactly where real
   logic conflicts live.
4. Decide on the `harness/` subsystem last and separately — it's a
   product/architecture decision (adopt pi's harness model vs keep
   ours vs run both), not something to fold into a mechanical file sync.
5. Regenerate `models.generated.ts` via `packages/ai/scripts/generate-models.ts`
   rather than merging it by hand.
