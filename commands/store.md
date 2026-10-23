---
description: 落库：把给定内容判重后存入 respire 记忆（标题事实句、important 带挂点）
---

请把以下内容存入 respire 记忆（rsrs CLI）：

"$ARGUMENTS"

流程（判后即存）：

1. 内容为空则先问用户要记什么。
2. 先 `rsrs recall "<内容核心词>" --titles --json` 判重；有同题候选则 **改＞并＞挂＞存**：能就地 update 改旧条、可合并则 `--merge-ids`，确属子项/相关才 `--parent <id>` 新挂，确无同题才新存。
3. 新存用 `rsrs remember "<正文>" --title "<事实句>" --importance important --parent <挂点id>`：标题写「主语＋动作＋结果」完整事实句（禁主题分类名、禁硬截断）；正文按 `【前因】/【行为】/【后果】` 三段；可复用结论必须带 `--parent`。
4. 回执 `status:"pending"`（判为相似未写入）时：转述候选给用户，由用户决断挂靠或 `--force`。
5. 敏感审查：口令、token、私钥、证件卡号禁入正文，只存用途/位置指针。存完回报短 id。
