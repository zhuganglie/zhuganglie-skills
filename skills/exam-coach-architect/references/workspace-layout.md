# 工作区布局

## 路径选择规则

- 优先使用用户明确给出的目标目录。
- 如果当前 `cwd` 路径包含 `/skills/`、`/.codex/skills/`、`/.agents/skills/`，视为不安全目录，不要在此写入用户工件。
- 如果当前目录安全且用户没有指定目标目录，默认创建 `runs/YYYY-MM-DD-<subject-slug>/`。
- 如果目标目录已存在且非空，不要静默覆盖。

## 推荐目录结构

```text
runs/2026-03-14-ap-calculus-bc/
├── AGENT.md
├── SOUL.md
├── LEARNER.md
├── knowledge/
│   ├── exam-map.md
│   ├── topics/
│   │   ├── paper-1-mcq.md
│   │   └── paper-2-frq.md
│   ├── rubrics/
│   │   ├── paper-1-mcq.md
│   │   └── paper-2-frq.md
│   ├── objectives/
│   │   ├── paper-1-mcq.md
│   │   └── paper-2-frq.md
│   └── examples/
├── memory/
│   ├── MEMORY.md
│   └── sessions/
│       └── _template.md
├── sources/
│   └── past-papers/
└── .agent/
    └── workflows/
        └── ap-calculus-bc.md
```

## 命名规范

- 科目 slug：小写连字符，例如 `ib-economics-hl`。
- 模块 slug：根据用户提供的模块名稳定转换为小写连字符，例如 `Part 2` -> `part-2`，`Paper 1 (MCQ)` -> `paper-1-mcq`。
- 工作流文件名必须与科目 slug 完全一致。
- `knowledge/exam-map.md` 中引用的 `topics/<module-slug>.md` 必须与真实文件名一致。

## 最低完整度

一个合格工作区至少应包含：

- 4 个根控制文件：`AGENT.md`、`SOUL.md`、`LEARNER.md`、`memory/MEMORY.md`
- 1 个训练路由文件：`knowledge/exam-map.md`
- 1 个 workflow 文件：`.agent/workflows/<subject-slug>.md`
- 每个模块各 1 个 topic / rubric / objective 文件
- 1 个 session 模板：`memory/sessions/_template.md`

`knowledge/examples/` 和 `sources/past-papers/` 可以先为空，但不要伪造内容。
