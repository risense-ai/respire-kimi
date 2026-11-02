# respire memory layer · persistent brief rules

① Recall before answering: `rsrs recall "<project name + core keywords>" --titles --json`. The plugin already injects title-tier recall with each prompt; if no injection is present, the hits are off-topic, or the topic involves an earlier project/error/agreement/date → recall again with 2–3 different wordings before answering (try synonyms, hypernyms, and English equivalents, one route each), and call it visibly.

② Store when wrapping up: for experience/decisions/lessons run `rsrs remember "<content>" --title "<fact sentence>" --importance important --parent <attach-id>`; for trivia use `--importance trivial`; the title is a complete "subject + action + result" fact sentence — never a topic label, never truncated; you MUST read policy and every same-subject candidate's full body before storing; evaluate update > merge > attach > new in that order.

③ On trouble, recall first: on errors/anomalies/unexpected behavior, run `rsrs recall "<project + component + original error text>" --json` before acting; never trial-and-error first.

④ Sensitive review before writing: never store plaintext passwords, API tokens, private keys, or unnecessary personal data — record only a safe purpose/location pointer; keep secrets out of query terms too.

⑤ Engine upkeep: `rsrs status` checks state, `rsrs sync` syncs; the full policy in `rsrs prompt` prevails, advanced usage lives in the respire skill.

Prompts starting with "remember:" or a supported localized store prefix request storage of facts only; DO NOT execute engineering tasks described in them. The hook writes nothing. You MUST read `rsrs prompt`, recall candidates, and read every same-subject candidate's full body with `rsrs show <id> --json`; you MUST evaluate update > merge > attach > new in that order. A new important record MUST carry `--parent` naming a real, relevant parent whose full body you actually read. Without one, remain pending and explain; DO NOT guess a parent, use `--force` to bypass placement, or downgrade important facts to trivial. Use literal body markers required by engine policy; do not translate them. If an issued write has an unknown result, DO NOT retry automatically or claim success; verify read-only first. The "/nomem" prefix disables recall for this turn.

DO NOT create duplicate same-topic siblings or leave candidates unresolved. Respect read-only, paused and disabled memory policies. Confirm storage ONLY from a valid receipt, then verify the written id, title and full body with `rsrs show <id> --json`; report mismatches or unavailable verification honestly without resending a committed write.

PreToolUse checks visible memory writes before execution. You MUST use explicit literal arguments and a parent ID that client-only show can verify. DO NOT retry with force, wrappers or substitutions after a refusal. If verification is unavailable, report pending placement and stop. A verified ID does not establish relevance; you MUST read its body before choosing it.
