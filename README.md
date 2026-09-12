# dsh-adversarial-roundtable — 多模型圆桌会议编排（DeepSeek Harness 常驻插件）

为 DeepSeek Harness 提供 `roundtable_models` 与 `roundtable` 两个工具，让多个接入模型按席位协作：
**先向用户确认阵容** → 规划者起草计划 → 独立审核者批判审核 → 讨论执行细节 → 执行者真实执行 → 独立验收者核对产物。

- 仓库：https://github.com/Nerdless-ship-it/dsh-adversarial-roundtable
- 许可证：[Apache-2.0](LICENSE)
- 当前版本：v0.5.0（tag `v0.5.0`）

## 阵容确认（v0.5.0）

用户说「开圆桌」时，模型**不该自己拍板各席用什么模型**。`roundtable` 在未带 `confirmed: true` 时会先通过
宿主的 `userQuestions` seam（即 `ask_user_question` 底下那条通路）向用户弹一张选择卡，用户选定后会议才开始：

| 题目 | 何时问 | 选项 |
|---|---|---|
| 阵容 | 总是 | 调用方提议（模型已传四席时）／**异源对抗（推荐）**／三方制衡（≥3 个 provider 在线时）／同源省钱／config 里的具名阵容／自定义 |
| 规模 | 未传 `scale`/`maxRounds`/`fixRounds` 时 | 标准（config 默认）／快速（1 轮讨论、0 修复）／深度（3 轮、2 修复），附最坏调用数估算 |
| 是否执行 | 未传 `runExecution` 时 | 全流程／只出计划 |

候选由代码生成：「当前会话模型」来自发起方 Agent 的请求头；「异源对抗」把审核/验收席换成偏好序里第一个
provider 不同且在线的模型（默认 grok-4.6 → deepseek-v4-pro → gpt-6-astra → claude-fable-5-1，`reviewPreference` 可改）。
选「自定义」时工具**不开会**，返回 `{ ok:false, needsLineup:true, custom, providers, candidates }`，由模型用
`ask_user_question` 逐席问清后带 `confirmed: true` 重调。

问不了人时（调用方是子代理/teammate → `DELEGATED_CALLER`，或无 answerer）：有完整绑定则带警告继续
（`lineup.source = "unconfirmed-child"`）；否则用 `defaultLineup`；都没有则报错要求显式绑定。取消（`ASK_ABORTED`）
直接抛「已取消」，不会降级开会。

插件同时在 system prompt 注册 `roundtable:policy` 段（order 紧跟 Agent Teams 的 `team:policy`），告诉模型：
只在用户明确要圆桌时用；不要自己定阵容，直接只传 `task` 让卡片来问；只有用户已逐席点名模型才 `confirmed: true`。
这一段是借鉴 `dsh-experimental-tool-agent-team` 的做法——协议放在代码注入的提示段里，而不是只靠工具描述。

## 席位与流程（5 席制）

| 席位 | 职责 | 模型绑定 |
|---|---|---|
| 规划者 | 起草计划、答疑、修订计划 | 必填 |
| 独立审核者 | 强制挑刺（APPROVE/REJECT），讨论中复核修订（CERTIFY/BLOCKED） | 可选，缺省复用规划者 |
| 执行者 | 讨论提问（RESOLVED 收敛）、真实执行、修复 | 必填 |
| 独立验收者 | 用工具实际核对产物（PASS/FAIL） | 可选，缺省复用执行者 |
| 主持人 | 轮次预算、收敛判定、兜底仲裁 | 编排代码，不消耗模型调用 |

裁定机制：判定类席位（审核/复核/验收/执行者提问）通过子代理 `structured_output` 工具回传
枚举裁定（`markerSource: structured`），provider 不支持时自动降级为文本标记「末行优先 → 独占成行
→ 全文唯一命中，歧义不猜」。纯思考席位（起草/审核/答疑/修订/复核/提问）通过 `toolFilter`
禁用全部工具，只有执行/修复/验收席能动手。规划者与执行者默认开启席位记忆：各自复用同一条
持续会话（起草→修订→答疑；执行→修复），后续轮只发增量内容，不重发任务与计划，
省 token；provider 不支持时自动退回一次性子代理。任一席位空输出、报错或超时都记入纪要并走保守分支；
调用次数或总时长预算耗尽时以当前状态收尾并落盘，不会因单点失败丢掉已有成果。

## 工具用法

- `roundtable_models`：列出可用 provider/模型与子代理 provider。
- `roundtable`：
  - 必填：`task`
  - 阵容：`confirmed`（true 时跳过选择卡，此时 `planner`/`executor` 必填）、`lineup`（config 具名阵容 id，等同已确认）、
    `planner`/`executor`/`reviewer`/`verifier`（未 confirmed 时作为「调用方提议」候选）
  - 规模：`scale`（`quick`/`standard`/`deep`）或显式 `maxRounds`（1-4）/`fixRounds`（0-2）；传了就不问规模
  - 可选：`runExecution`（传了就不问是否执行）、`verbosity`（`summary` 默认 / `full`）、`seatTimeoutMs`（0 = 不限）、
    `totalTimeoutMs`（整场总超时，0 = 不限）、`maxCalls`（子代理调用上限，默认 24，3-40）、
    `unknownVerdictPolicy`（验收无明确裁定时：`manual` 默认 / `fail` 进修复 / `pass`）、
    `subagentProvider`（缺省优先 spawn）、`seatMemory`（席位记忆，默认 true）
  - 返回：裁定与统计（`lineup`{source,planner,reviewer,executor,verifier}/`scale`/`reviewVerdict`/`converged`/`verdict`/`callsUsed`/`elapsedMs`/`independence`/
    `degraded`/`budgetExhausted`/`stageReached`/`features`/`seatFailures`）、
    `transcriptPath`（完整纪要 markdown 路径）；用户选「自定义」时返回 `{ ok:false, needsLineup:true, ... }`；
    `summary` 模式下 `phases` 只含标记与统计，正文全在纪要文件里

## 挂载配置（可选）

补丁行可传 config，省去每次调用都写参数：

```yaml
- insert:
    - id: roundtable
      name: 'dsh-adversarial-roundtable'
      config:
        # —— 阵容确认（v0.5.0）——
        confirmLineup: true        # false 恢复 v0.4 行为：不弹卡，直接按传入绑定开会
        policySection: true        # false 不注入 roundtable:policy 提示段
        reviewPreference:          # 异源对抗时审核/验收席的偏好序（provider 与当前会话不同且在线者优先）
          - { provider: grok, model: grok-4.6 }
          - { provider: deepseek-official, model: deepseek-v4-pro }
        lineups:                   # 具名阵容：出现在选择卡里，也可用 lineup: <id> 直接选用
          - id: cheap
            name: 省钱局
            description: 四席全走 flash
            planner:  { provider: deepseek-official, model: deepseek-flash }
            executor: { provider: deepseek-official, model: deepseek-flash }
            # reviewer/verifier 缺省复用 planner/executor
        defaultLineup: cheap       # 问不了人（子代理调用）且未传绑定时的兜底
        # —— 会议参数 ——
        defaultMaxRounds: 3        # 1-4
        defaultFixRounds: 1        # 0-2
        defaultVerbosity: summary  # summary | full
        defaultSeatTimeoutMs: 0    # 0 = 不限
        defaultTotalTimeoutMs: 0   # 0 = 不限
        defaultMaxCalls: 24        # 3-40
        defaultUnknownVerdictPolicy: manual  # manual | fail | pass
        seatMemory: true            # 席位记忆：规划者/执行者跨轮复用持续会话
        structuredVerdicts: true   # false 强制文本标记
        restrictThinkingSeats: true  # false 不禁用思考席工具
        subagentProvider: spawn    # 缺省自动选择
        transcriptDir: ~/.dsh/roundtable-transcripts
        quiet: false               # true 关闭启动日志
```

## 测试

```bash
git clone https://github.com/Nerdless-ship-it/dsh-adversarial-roundtable
cd dsh-adversarial-roundtable
npm install
npm test
```

`test-internals.mjs`（38 项）覆盖标记提取、结构化裁定优先级与能力错误识别；
`test-flow.mjs`（113 项）用假子代理跑完整会议，零模型调用验证结构化/工具禁用/能力降级/
预算耗尽/UNKNOWN 策略/席位记忆（含 cold resume）/容错/落盘/返回体裁剪，以及 v0.5.0 的
阵容确认门（候选生成与顺序、三题/跳题、自定义不开会、具名阵容与离线剔除、子代理降级、取消、confirmLineup:false）。
测试零模型调用，不需要配置任何 provider。devDependencies 把 `@deepseek-ai/dsh-{tools,llm,subagent}`
钉在 `0.1.5-rc.2`（真机验证所用版本）：npm 上这几个包的 `latest` 标签指向过期的 `0.0.1-rc.1`，
裸装 `latest` 会解析到错误版本，所以显式钉版本并提交 lockfile，`npm ci` 可完全复现。

## 安装（推荐：GitHub git 依赖）

每台机器只需做一次：

```bash
# 1. 安装插件（dsh plugin 底层是 pnpm，原生支持 git 依赖）
dsh plugin --profile web add github:Nerdless-ship-it/dsh-adversarial-roundtable#v0.5.0

# 2. 在 ~/.dsh/cordis.patch.yml 末尾追加两行：
# - insert:
#     - id: roundtable
#       name: 'dsh-adversarial-roundtable'

# 3. 重启 dsh web
```

`@deepseek-ai/dsh-{tools,llm,subagent}` 在 `package.json` 里声明为 **optional peerDependencies**，这是
刻意为之，不要"顺手修好"：它们是宿主机（dsh 本体）提供的，插件运行时会从 profile 的
`node_modules` 解析到宿主那一份。若不标 optional，pnpm 会把 peer 自动装进当前 project
（`auto-install-peers` 默认开启）——那等于在同一进程里塞进第二份 dsh-tools / cordis 注册表，
插件会以难以定位的方式出错。更糟的是这几个包在 npm 上的 `latest` 标签仍停留在过期的
`0.0.1-rc.1`，其依赖树里的 `@deepseek-ai/dsh-type-meta` 已从 registry 下架，会直接
`ERR_PNPM_FETCH_404` 让安装整体失败。因此这里显式收窄到 `>=0.1.5-rc.2` 并标记 optional，
让安装器一个 peer 都不装。

## 升级（GitHub 路线）

```bash
# 安装机执行（固定到新 tag）：
dsh plugin --profile web add github:Nerdless-ship-it/dsh-adversarial-roundtable#v0.5.0
# 然后重启 dsh web。补丁行不变，无需重复配置。
```

发布侧（维护者）：改代码 → 提交 → `git tag v0.5.0 && git push --tags`。

## 备选安装：本地离线包（一键脚本）

```bash
tar xzf dsh-adversarial-roundtable-0.5.0.tgz
bash dsh-adversarial-roundtable/install.sh    # 可选 --profile <name>，默认 web
# 脚本自动完成：源码落位、语法检查、装入 profile store、写补丁行（幂等）、组成校验
# 然后重启 dsh web
```

Windows 上用 PowerShell 脚本，逻辑与 install.sh 等价：

```powershell
cd dsh-adversarial-roundtable
# PowerShell 7+
pwsh -File install.ps1                        # 可选 -Profile <name>，默认 web
# Windows PowerShell 5.1（Windows 自带，本插件在 5.1 上实测通过）
powershell -ExecutionPolicy Bypass -File install.ps1
```

手动拷贝（不想用脚本时）：

```bash
mkdir -p ~/.dsh/plugins
tar xzf dsh-adversarial-roundtable-0.5.0.tgz -C ~/.dsh/plugins/
mkdir -p ~/.dsh/profiles/node_modules
cp -R ~/.dsh/plugins/dsh-adversarial-roundtable ~/.dsh/profiles/node_modules/dsh-adversarial-roundtable
# 再按上文第 2、3 步加补丁行并重启
```

注意：包必须是实体拷贝而非 symlink（Node 按真实路径解析 peer 依赖，symlink 会失败）。

## 本地开发

- 仓库根目录就是包根目录（`git clone` 下来的目录即 `dsh plugin add` 识别的包）
  - `index.mjs` — 插件实现（ESM，导出 `name`/`inject`/`apply`，peer 依赖 dsh-tools/dsh-llm/dsh-subagent）
  - `package.json` — 包元数据（`dsh-adversarial-roundtable`）
  - `test-internals.mjs` / `test-flow.mjs` — 测试（`npm test`，需先 `npm install`）
  - `install.sh` / `install.ps1` — 离线一键安装脚本（类 Unix 与 Windows）
  - `LICENSE` / `NOTICE` — Apache-2.0
- 手动安装位置：`~/.dsh/profiles/node_modules/dsh-adversarial-roundtable/`
  （若改用 `dsh plugin add` 管理，请删除该手动副本避免双份）
- 挂载点：`~/.dsh/cordis.patch.yml` 的 `roundtable plugin:start/end` 块，其中 `name` 为包名
- 改完源码要生效：重跑 `install.sh` / `install.ps1`，或重新 `dsh plugin add` 后再重启 dsh。
  store 里放的是实体拷贝（Node 按真实路径解析 peer 依赖，symlink 会失败），不会自动跟随仓库。

## 已验证

- 2026-09-04 原型（3 席）真机验证：规划/讨论/执行闭环 ✅
- 2026-09-04 5 席真机验证（jsonfmt.html 任务，最终 PASS）：审核打回、讨论复核、
  独立验收、修复循环全流程 ✅；产物独立复验（存在性/零外部依赖/JS 语法）✅
- 2026-09-04 重启后真实验证：真实 profile 二次启动日志含
  `[roundtable] host plugin active`、零错误、主服务器重启后工具可用 ✅
- 2026-09-04 v0.4.0 席位记忆真机验证：REJECT 修订 + 讨论答疑走持续会话增量、
  cold resume 后正常续轮、7 次调用 PASS、产物与纪要核验通过 ✅
- 2026-09-04 v0.2.0 代码审查修复：单元测试 28 项 + 流程测试 33 项全通过、真实 profile
  启动零错误 ✅
- 已知观察：claude-fable-5-1 路由经 pi-ai 网关偶发空输出报错，fail-safe 自动兜底；
  建议审核席优先绑 grok-4.6 / deepseek-v4-pro

## v0.5.0 变更

**阵容确认门 + 协议提示段**：详见上文「阵容确认」。实现要点：`inject` 新增 `systemPrompt`、`userQuestions`
（均为 dsh-base 根平面服务，任何 profile 都有）；候选/问题/答案解析是纯函数（`buildCandidates`/`buildQuestions`/
`readAnswers`），通过 `__internals` 暴露给测试；当前会话模型从发起方 `agent.session.requestHeader().config` 读取，
创建选项兜底。`planner`/`executor` 不再必填。返回值与纪要头新增 `lineup.source` 与 `scale`。
测试假子代理的 `assistant/message` 事件补上了 `stream: []`（真实 `finalAssistantOutput` 会读它，此前 S12/S15 在
新版 dsh-subagent 下失败）。

## v0.4.0 变更

**席位记忆（持续会话复用，省 token）**：规划者（起草→审核修订→答疑）与执行者（执行→修复）
各自在一条持续会话里跨轮工作，后续轮只发增量提示词（审核意见/提问清单/验收问题），
不重发任务与完整计划。实现要点：持续子代理每轮结束会被运行时自动回收，下一轮消息触发
cold resume 出新的 Agent 对象，因此每个轮次都重新解析 live session、按日志 seq 边界读取
本轮的 `turn/end` 与最终输出；provider 不支持或运行中失败时全局退回一次性子代理。
真机验证 7 次调用全程 PASS（规划者 session → session+ 增量答疑）。已知代价：每个子代理
每轮结束会向主会话投递一条结算通知（"Background subagent … finished"），属运行时行为。

## v0.3.0 变更

- **结构化裁定**：审核/复核/验收/执行者提问四类判定席改为通过 `outputSchema` 回传枚举
  `verdict`（或 `resolved` 布尔），彻底告别"从正文猜标记"；provider 不支持时自动降级为
  v0.2.0 文本提取并记 warning。真机验证 gemini/deepseek 均正确回传（`markerSource: structured`）。
- **纯思考席禁工具**：起草/审核/答疑/修订/复核/提问六种席位 `toolFilter: {allow: []}`，
  杜绝规划者"顺手执行"污染工作区；执行/修复/验收席不受限。
- **预算护栏**：`maxCalls`（默认 24）+ `totalTimeoutMs`；耗尽时抛内部信号，主持人记录、
  以 `stageReached` 标注停在哪、纪要照常落盘，返回 `budgetExhausted: true`。
- **UNKNOWN 处置策略**：`unknownVerdictPolicy` manual/fail/pass，标记注明推导（`无标记→FAIL`）。
- 其他：`subagentProvider` 可指定并校验、`roundtable_models` 返回 `version`、纪要头部记录
  特性开关与预算、测试增至 95 项。

## v0.2.0 变更

修复三个正确性缺陷：

1. **判定标记误判**：`CERTIFY`/`PASS`/`RESOLVED` 原先在全文正则匹配，审核者写「未达到
   CERTIFY 标准…BLOCKED」会被误判为收敛、验收者写「没有 FAIL 项…PASS」会被误判为失败、
   执行者写「澄清后我会回复 RESOLVED」会造成假收敛跳过整个讨论阶段。改为末行优先 +
   词边界 + 歧义不猜。
2. **子代理句柄泄漏**：`await run.result` 抛错时 `dispose()` 被跳过，改用 `try/finally`。
3. **单席位异常摧毁整场会议**：任一席位抛错会让前面所有轮次的成果随异常丢失。现在捕获
   进 `phases`/`seatFailures`，返回 `degraded: true`，会议继续。

新增：完整纪要落盘 + 返回体精简（`verbosity`）、`model` id 预校验、席位超时
（`seatTimeoutMs`）、独立性标记（`independence`）、成本统计（`callsUsed`/`elapsedMs`）、
挂载 config（默认值/纪要目录/`quiet`）、提示词数据围栏、席位标签带阶段与轮次。

## 许可证

[Apache License 2.0](LICENSE)，版权人 Nerdless-ship-it（见 [NOTICE](NOTICE)）。
`@deepseek-ai/dsh-*` 是 peer 依赖，本仓库不打包也不转发它们，各自遵循其自身许可证。

## 贡献

- 提交前请保证 `npm test` 全绿（151 项，零模型调用，不需要任何 API key 或 provider 配置）。
- 判定逻辑的改动优先补 `test-internals.mjs`；编排分支的改动优先补 `test-flow.mjs` 里的假子代理场景。
- 行为有变化时，请在 README 变更记录里补一段，说明改了什么、为什么改。
