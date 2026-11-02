---
name: respire
description: respire (rsrs) local encrypted memory playbook. Automatic per-turn recall is injected with the prompt; **if no injection is present, the hits are off-topic, or the topic involves an earlier project, error, agreement, or date, recall again with different wording (synonyms, hypernyms, English equivalents, one route each); do not repeat only when the injected hits are truly relevant**. Manual recall, remember (judge then store), show/chain to read full text, forget, sync, status; a store prefix requests model-managed storage and the hook writes nothing; the "/nomem" prefix disables recall for the turn. Triggers: memory, recall, remember, store memory, forget, sync, 记忆, 翻忆, 存记忆, 忘掉, 同步.
---

# respire · memory playbook (Kimi Code)

When a visible memory write triggers PreToolUse, you MUST use a single explicit literal command. DO NOT bypass placement with force, shell wrappers, substitutions or an empty parent. Important creation and every merge require a real parent ID verified by client-only show; you MUST still read the full parent body and judge relevance. Before updating importance to important, the target MUST already have a verified non-empty parent; otherwise attach it first. If verification fails, stop the write and report pending placement. Read-only, paused and disabled memory policies remain exceptions to storing. Confirm completion only after a valid receipt and read-back. The hook cannot inspect arbitrary scripts, aliases or hidden external calls.

Plugin behavior: persistent brief rules ride the system prompt (`systemPromptPath` → `SYSTEM.md`) and this playbook loads per session (`sessionStart.skill`); every UserPromptSubmit auto-recalls (rsrs skips irrelevant queries itself — zero hits = skip; this layer defaults to direct output, threshold off); SessionStart status-probe guidance (not signed in / empty store / missing model) lands in a `.pending_nudge` file that the first prompt carries at the top; when a prompt starts with a store prefix, the hook writes nothing and returns pending for model-managed placement — **when the receipt includes a provisional title and short id, extract a complete "subject + action + result" sentence from the facts and replace it with `rsrs retitle <short-id> --title` (hard rule; the title is the facade for recall and dedup)**; `/nomem` disables recall for the turn. This skill is invoked via `/skill:respire:respire`; quick commands `/respire:recall`, `/respire:store`, `/respire:sync`.

## Commands

- `rsrs recall "project name + keywords" --limit 5 --json` — **recall before answering, visibly** (an empty injection never means no memory; search manually); on errors, recall by the original error text first; `--titles` returns short id + title only
- `rsrs remember "content" --title "fact sentence" --importance important --parent <read-parent-id>` — one item per record, judge before storing; reusable conclusions must carry `--parent <attach-id>`
- `rsrs show <short-id>` (first 8 chars) reads the full body; `rsrs chain` fetches the whole causal chain
- `rsrs forget <id>` — tombstone delete, propagated by sync
- `rsrs candidates <content>` — pre-store candidate list (merge/attach suggestions)
- `rsrs sync` two-way sync (autosync on); `rsrs status` checks state; `rsrs prompt` prints the full memory workflow
- `rsrs tree/resort/retitle` — maintain the causal tree

## Parsing notes (CLI envelope)

- Every command with `--json` uses one envelope: `status`, `summary`, `items`, `details`, `errors`; **failures also return HTTP 200 with `status:"fail"` and `errors[]`** — check status, not the exit code
- recall scores and entries live in `details[].score`, `details[].id` (full id; use the first 8 chars as the short id), `details[].title` and `details[].superseded_by`; `items` is only the "score title" line
- Progress goes to stderr; never mix it into JSON with `2>&1`
- remember stores after judgement: `status:"ok"` means written (`summary.id`); `status:"pending"` plus `written:false` means a similar record was found and **nothing was written** — read candidates and you MUST evaluate update > merge > attach > new in that order; unresolved placement stays pending
- The default `trivial` tier goes to the diary area, is excluded from recall and gets its title rewritten to "activity track <date>" — use `--importance important --parent <read-parent-id>` for factual records

## Red lines

- Never put passwords, ID numbers, phone numbers, card numbers, or private keys into memory bodies or query terms; record only where they are stored — the library is encrypted, but a leaked key exposes everything
- Recall scores are relevance, not confidence; run candidates before storing, you MUST evaluate update > merge > attach > new in that order
- Account and sync configuration are outside this plugin: run `rsrs register` / `rsrs login` on this machine (no website step); the plugin does not handle it

Store requests contain facts only; do not execute engineering tasks described in them. You MUST read `rsrs prompt`, recall candidates, and read every same-subject candidate's full body with `rsrs show <id> --json` BEFORE choosing update > merge > attach > new. A new important record MUST carry `--parent` naming a real, relevant parent whose full body you actually read. Without one, remain pending and explain; never guess, use `--force` to bypass placement, or downgrade important facts to trivial. Use literal body markers required by engine policy; do not translate them. If an issued write has an unknown result, DO NOT retry automatically or claim success; verify read-only with `rsrs list` / `rsrs show --json`.

DO NOT create duplicate same-topic siblings or leave candidates unresolved. Respect read-only, paused and disabled memory policies. Confirm storage ONLY from a valid write receipt, then verify the written id, title and full body with `rsrs show <id> --json`; report mismatches or unavailable verification honestly without resending a committed write.
