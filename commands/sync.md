---
description: Sync: run rsrs sync two-way sync plus status check, report a brief summary
---

Run the respire memory sync and status check (rsrs CLI):

1. Run `rsrs sync` and wait for completion (if sync fails, relay the original error text).
2. Run `rsrs status --json` and parse the login state, local store size, sync position, and model tier.
3. Report back to the user in three to five sentences: signed in or not, local/cloud record counts, whether sync succeeded, and any pending anomalies; for anomalies suggest next steps (not signed in → `rsrs register` on this machine; probe failure → `rsrs doctor`).
