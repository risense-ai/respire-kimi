---
description: Recall: search the respire memory store by "project name + keywords" (title tier), then read selected full texts
---

Perform a respire memory recall (rsrs CLI, read-only):

1. If arguments are given: run `rsrs recall "$ARGUMENTS" --titles --json`; **the query must contain the project name**. If no arguments: first ask the user what to look up (project name + core keywords).
2. Results are title tier (score + 8-char short id + title). Pick on-topic entries by title and read each full body with `rsrs show <short-id> --json`; for entries marked `superseded_by`, read the replacing record first.
3. Zero hits or off-topic hits: re-query with 2–3 different wordings (synonyms, hypernyms, English equivalents, one route each) before concluding "no memory".
4. Briefly relay the key points of the hits to the user, noting the short ids for reference.
