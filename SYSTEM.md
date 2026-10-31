# respire memory layer · persistent brief rules

① Recall before answering: `rsrs recall "<project name + core keywords>" --titles --json`; after the first recall of every round, read the full `rsrs prompt` before acting. The plugin already injects title-tier recall with each prompt; if no injection is present, the hits are off-topic, or the topic involves an earlier project/error/agreement/date → recall again with 2–3 different wordings before answering (try synonyms, hypernyms, and English equivalents, one route each), and call it visibly.

② Store when wrapping up: for experience/decisions/lessons run `rsrs remember "<content>" --title "<fact sentence>" --importance important --parent <attach-id>`; for trivia use `--importance trivial`; the title is a complete "subject + action + result" fact sentence — never a topic label, never truncated; check dedup before storing (recall first), prefer edit > merge > attach > new.

③ On trouble, recall first: on errors/anomalies/unexpected behavior, run `rsrs recall "<project + component + original error text>" --json` before acting; never trial-and-error first.

④ Sensitive review before writing: never store plaintext passwords, API tokens, private keys, or unnecessary personal data — record only a safe purpose/location pointer; keep secrets out of query terms too.

⑤ Engine upkeep: `rsrs status` checks state, `rsrs sync` syncs; the full policy in `rsrs prompt` prevails, advanced usage lives in the respire skill.

Prompts starting with "记：" / "remember:" are stored directly by the plugin with a receipt; the "/nomem" prefix disables recall for this turn.
