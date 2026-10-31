---
description: Store: dedup-check the given content into the respire memory (fact-sentence title, important with parent)
---

Store the following content into the respire memory (rsrs CLI):

"$ARGUMENTS"

Procedure (judge then store):

1. If the content is empty, first ask the user what to remember.
2. Run `rsrs recall "<content core keywords>" --titles --json` to check dedup; with same-subject candidates prefer **edit > merge > attach > new**: update the old record in place when possible, merge with `--merge-ids` when applicable, attach as a child with `--parent <id>` only when it is genuinely a sub-item or related, and create new only when nothing matches.
3. For a new record use `rsrs remember "<content>" --title "<fact sentence>" --importance important --parent <attach-id>`: the title is a complete "subject + action + result" fact sentence (never a topic label, never truncated); the body uses the `【前因】/【行为】/【后果】` (cause/action/outcome) sections; reusable conclusions must carry `--parent`.
4. On receipt `status:"pending"` (judged similar, nothing written): relay the candidates to the user and let them decide to attach or `--force`.
5. Sensitive review: never put passwords, tokens, private keys, or ID/card numbers into the body — store only a purpose/location pointer. Report the short id after storing.
