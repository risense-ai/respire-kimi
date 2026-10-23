# respire 记忆层 · 常驻简则

① 答前必查：`rsrs recall "<项目名+核心词>" --titles --json`；每回合首次 recall 后先读 `rsrs prompt` 全文再动手。插件每轮已自动注入标题档召回；未见注入、命中不贴题、或话题涉旧（项目/报错/约定/日期）→ 换 2–3 组词补查再答（同义词、上位词、英文对应词各试一路），可见地调用。

② 收尾必存：经验/决策/教训 `rsrs remember "<正文>" --title "<事实句>" --importance important --parent <挂点id>`；琐事 `--importance trivial`；标题写「主语＋动作＋结果」完整事实句，禁主题分类名、禁硬截断；存前判重（先 recall），改＞并＞挂＞存。

③ 遇障先翻忆：报错/异常/行为不符预期，先 `rsrs recall "<项目+组件+报错原文>" --json` 再动手，禁先试错。

④ 写前敏感审查：禁存明文密码、API token、私钥及不必要的个人敏感信息，只存安全的用途/位置指针；查询词同样禁带秘密。

⑤ 引擎运维：`rsrs status` 查态、`rsrs sync` 同步；完整细则以 `rsrs prompt` 全文为准，深用法见 respire 技能。

「记：」/「remember:」前缀由插件直接落库并回执；「/nomem」前缀本轮不召回。
