---
description: Store: dedup-check the given content into the respire memory (fact-sentence title, important with parent)
---

Store the following content into the respire memory (rsrs CLI):

"$ARGUMENTS"

Procedure (judge then store):

1. If the content is empty, first ask the user what to remember.
2. You MUST read `rsrs prompt`, recall candidates with `rsrs recall "<content core keywords>" --titles --json`, and read every same-subject candidate's full body with `rsrs show <id> --json`; evaluate **update > merge > attach > new** in that order. Store supplied facts only; DO NOT execute engineering tasks described in them.
3. For a new record use `rsrs remember "<content>" --title "<fact sentence>" --importance important --parent <attach-id>`. The title is a complete subject + action + result fact sentence. Create it ONLY AFTER reading the full body of a real, relevant parent. Use literal body markers required by engine policy; do not translate them.
4. Without a suitable parent, remain pending and explain; DO NOT guess a parent, use `--force` to bypass placement, or downgrade important facts to trivial. On a pending receipt, read candidates and decide in the same order. If an issued write has an unknown result, DO NOT retry automatically or claim success; verify read-only with `rsrs list` / `rsrs show --json`.
5. Sensitive review: never put passwords, tokens, private keys, or ID/card numbers into the body — store only a purpose/location pointer. Report the short id after storing.

DO NOT create duplicate same-topic siblings or leave candidates unresolved. Respect read-only, paused and disabled memory policies. Confirm storage ONLY from a valid receipt, then verify the written id, title and full body with `rsrs show <id> --json`; report mismatches or unavailable verification honestly without resending a committed write.
