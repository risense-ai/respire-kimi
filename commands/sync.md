---
description: 同步：rsrs sync 双向同步记忆库并查态，回报简要摘要
---

请执行 respire 记忆同步与查态（rsrs CLI）：

1. 运行 `rsrs sync`，等待完成（同步失败也把报错原文带出来）。
2. 运行 `rsrs status --json`，解析登录态、本地库量、同步位点与模型档。
3. 用三五句中文向用户回报：是否已登录、本地/云端各多少条、同步是否成功、有无待处理异常；异常给出下一步建议（未登录→rsrs.rs 注册后 rsrs register；探测失败→rsrs doctor）。
