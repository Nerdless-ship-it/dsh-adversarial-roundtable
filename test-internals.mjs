// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Nerdless-ship-it
// 内部判定逻辑单元测试：node test-internals.mjs
// 覆盖 v0.1.0 里因全文正则匹配导致的误判场景。
import { __internals } from "./index.mjs";

const { pickMarker, resolvedInText, verdictOf, clampInt, sameBinding, truncate, textOf } = __internals;

let pass = 0;
let fail = 0;

function check(name, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (ok) {
    pass += 1;
  } else {
    fail += 1;
    console.log(`✗ ${name}\n   期望: ${JSON.stringify(expected)}\n   实际: ${JSON.stringify(actual)}`);
  }
}

// ---- pickMarker: 末行优先 ----
check("末行 CERTIFY", pickMarker("问题都已解决。\nCERTIFY", ["BLOCKED", "CERTIFY"]), "CERTIFY");
check("末行 BLOCKED", pickMarker("1. 仍缺回滚步骤\nBLOCKED", ["BLOCKED", "CERTIFY"]), "BLOCKED");

// ---- v0.1.0 的误判场景（回归测试）----
check(
  "正文提到 CERTIFY 但末行 BLOCKED（旧版误判为收敛）",
  pickMarker("修订仍未达到 CERTIFY 标准，问题 2 未解决。\nBLOCKED", ["BLOCKED", "CERTIFY"]),
  "BLOCKED",
);
check(
  "正文提到 FAIL 但末行 PASS（旧版误判为失败）",
  verdictOf("全部核对项均通过，没有任何 FAIL 项。\nPASS"),
  "PASS",
);
check(
  "正文提到 PASS 但末行 FAIL",
  verdictOf("第 3 项本应 PASS，实际缺失。\nFAIL"),
  "FAIL",
);
check(
  "末行带标点也能识别",
  pickMarker("结论如下。\n裁定：REJECT", ["REJECT", "APPROVE"]),
  "REJECT",
);
check(
  "标记独占一行但不在末行",
  pickMarker("APPROVE\n\n（补充说明：建议补充回滚步骤）", ["REJECT", "APPROVE"]),
  "APPROVE",
);
check(
  "全文同时出现两个标记且末行无标记 → 不猜",
  pickMarker("可能 APPROVE 也可能 REJECT，我无法判断。", ["REJECT", "APPROVE"]),
  null,
);
check("空文本 → null", pickMarker("", ["FAIL", "PASS"]), null);
check("无标记 → UNKNOWN", verdictOf("我检查了产物，一切看起来都不错。"), "UNKNOWN");
check("PASSED 不应命中 PASS（词边界）", verdictOf("所有测试 PASSED-ISH 状态未知"), "UNKNOWN");

// ---- resolvedInText: 首行专属 ----
check("首行 RESOLVED", resolvedInText("RESOLVED\n我将按计划执行。"), true);
check(
  "正文提到 RESOLVED 但仍在提问（旧版假收敛）",
  resolvedInText("1. 路径是否为绝对路径？\n2. 这些澄清后我会回复 RESOLVED 再开工。"),
  false,
);
check("独占成行的 RESOLVED", resolvedInText("说明如下：\nRESOLVED\n开始执行", true), true);
check("空文本不算收敛", resolvedInText(""), false);

// ---- clampInt ----
check("clampInt 缺省", clampInt(undefined, 2, 1, 4), 2);
check("clampInt 上限", clampInt(99, 2, 1, 4), 4);
check("clampInt 下限", clampInt(-5, 1, 0, 2), 0);
check("clampInt 非数", clampInt("abc", 2, 1, 4), 2);
check("clampInt 取整", clampInt(3.7, 2, 1, 4), 3);

// ---- sameBinding ----
check(
  "同绑定",
  sameBinding({ provider: "a", model: "m" }, { provider: "a", model: "m" }),
  true,
);
check(
  "异绑定",
  sameBinding({ provider: "a", model: "m" }, { provider: "a", model: "n" }),
  false,
);
check("空绑定", sameBinding(null, { provider: "a", model: "m" }), false);

// ---- textOf ----
check(
  "提取 text 块",
  textOf({ output: [{ type: "text", text: " hi " }, { type: "tool_use" }, { type: "text", text: "there" }] }),
  "hi \nthere",
);
check("无 output", textOf({}), "");
check("null 结果", textOf(null), "");

// ---- truncate ----
check("不截断", truncate("abc", 10), "abc");
check("截断带提示", truncate("abcdef", 3).startsWith("abc\n…"), true);

// ---- judge: 结构化优先，文本兜底 ----
const { judge, judgeResolved, isUnsupportedCapability, SCHEMA_VERIFY } = __internals;
check(
  "结构化 verdict 优先于正文",
  judge({ text: "PASS", structured: { verdict: "FAIL", report: "缺第 2 项" } }, ["FAIL", "PASS"], "report"),
  { marker: "FAIL", source: "structured", text: "缺第 2 项" },
);
check(
  "结构化字段非法枚举 → 退回文本",
  judge({ text: "全过。\nPASS", structured: { verdict: "OK", report: "x" } }, ["FAIL", "PASS"], "report"),
  { marker: "PASS", source: "text", text: "全过。\nPASS" },
);
check(
  "结构化正文为空时保留原文",
  judge({ text: "原文", structured: { verdict: "PASS", report: "  " } }, ["FAIL", "PASS"], "report").text,
  "原文",
);
check("无结构化无标记 → none", judge({ text: "嗯", structured: undefined }, ["FAIL", "PASS"], "report"), {
  marker: null,
  source: "none",
  text: "嗯",
});
check(
  "judgeResolved 结构化 true",
  judgeResolved({ text: "", structured: { resolved: true, content: "直接干" } }),
  { resolved: true, source: "structured", text: "直接干" },
);
check(
  "judgeResolved 文本假收敛不中招",
  judgeResolved({ text: "1. 路径？\n2. 之后我回复 RESOLVED", structured: undefined }).resolved,
  false,
);
check("能力错误识别（code）", isUnsupportedCapability({ code: "UNSUPPORTED_CAPABILITY", message: "" }), true);
check(
  "能力错误识别（message）",
  isUnsupportedCapability({ message: 'subagent provider "acp" does not support the "toolFilter" capability' }),
  true,
);
check("普通错误不误识别", isUnsupportedCapability(new Error("boom")), false);
check("verify schema 为对象根且含枚举", [SCHEMA_VERIFY.type, SCHEMA_VERIFY.properties.verdict.enum], ["object", ["PASS", "FAIL"]]);

console.log(`\n单元测试：${pass} 通过，${fail} 失败`);
process.exit(fail === 0 ? 0 : 1);
