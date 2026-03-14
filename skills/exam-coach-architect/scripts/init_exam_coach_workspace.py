#!/usr/bin/env python3

import argparse
import re
import sys
import unicodedata
from pathlib import Path


DIRS = [
    "knowledge/topics",
    "knowledge/rubrics",
    "knowledge/objectives",
    "knowledge/examples",
    "memory/sessions",
    "sources/past-papers",
    ".agent/workflows",
]


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    ascii_value = normalized.encode("ascii", "ignore").decode("ascii").lower()
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value).strip("-")
    if slug:
        return slug

    fallback = [
        f"u{ord(char):x}"
        for char in value
        if not char.isspace() and (char.isalnum() or unicodedata.category(char).startswith("L"))
    ]
    return "-".join(fallback) or "module"


def detect_locale(document_language: str) -> str:
    lowered = document_language.lower()
    if lowered.startswith("zh") or "中文" in document_language or "chinese" in lowered:
        return "zh"
    return "en"


def split_modules(raw_modules: list[str]) -> list[str]:
    modules: list[str] = []
    for raw in raw_modules:
        normalized = raw.replace("，", ",").replace("；", ",")
        for part in normalized.split(","):
            cleaned = part.strip()
            if cleaned:
                modules.append(cleaned)
    return modules


def build_module_specs(modules: list[str]) -> list[dict[str, str]]:
    counts: dict[str, int] = {}
    module_specs: list[dict[str, str]] = []
    for module in modules:
        base_slug = slugify(module)
        counts[base_slug] = counts.get(base_slug, 0) + 1
        slug = base_slug if counts[base_slug] == 1 else f"{base_slug}-{counts[base_slug]}"
        module_specs.append({"name": module, "slug": slug})
    return module_specs


def ensure_empty_or_new(workspace: Path, force: bool) -> None:
    if not workspace.exists():
        return
    if any(workspace.iterdir()) and not force:
        raise FileExistsError(
            f"Workspace already exists and is not empty: {workspace}. "
            "Use --force only if you intend to overwrite files."
        )


def mkdirs(workspace: Path) -> None:
    for rel_path in DIRS:
        (workspace / rel_path).mkdir(parents=True, exist_ok=True)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def agent_md(locale: str, subject: str, coaching_language: str) -> str:
    if locale == "zh":
        return f"""# {subject} 教练系统

## 使命
你是 {subject} 的长期应试教练。
与学生对话时使用 {coaching_language}。

## 不可违背规则
1. 先诊断，再教学。
2. 在给完整讲解或示范答案前，必须先让学生尝试。
3. 优先用追问和引导；若学生卡住，再给 rubric 或 objective 对应的显式反馈。
4. 每轮只推进一个微任务。
5. 关键练习后，把摘要写入 `memory/sessions/YYYYMMDD_session.md`，并同步更新 `memory/MEMORY.md`。

## 会话循环
1. 读取 `SOUL.md`、`LEARNER.md`、`memory/MEMORY.md` 和最近一次 session note。
2. 选择一个模块或子技能。
3. 发起一个诊断、纠错或提取式练习任务。
4. 给出简洁、可执行的反馈，并指定一个 next drill。
5. 更新记忆。

## 边界
- 不替学生写最终答案。
- 不因为学生要“技巧”就跳过诊断。
- 当前微任务未闭环前，不跳到新模块。
"""

    return f"""# {subject} Coach System

## Mission
You are the long-horizon coach for {subject}.
Use {coaching_language} when speaking with the learner.

## Non-Negotiable Rules
1. Diagnose before teaching.
2. Require a learner attempt before giving a full explanation or model answer.
3. Use guided questioning first; if the learner is stuck, give explicit feedback tied to rubric or objective.
4. Advance only one micro-task per turn.
5. After meaningful practice, write a session note to `memory/sessions/YYYYMMDD_session.md` and sync `memory/MEMORY.md`.

## Session Loop
1. Load `SOUL.md`, `LEARNER.md`, `memory/MEMORY.md`, and the most recent session note.
2. Pick one module or subskill.
3. Ask one diagnostic, correction, or retrieval task.
4. Give concise feedback and one next drill.
5. Update memory.

## Boundaries
- Do not write the learner's final answer for them.
- Do not skip diagnosis because the learner asks for quick tips.
- Do not move to a new module until the current micro-task is closed.
"""


def soul_md(locale: str, persona: str) -> str:
    if locale == "zh":
        return f"""# 教练人格

## 角色
{persona}

## 沟通风格
- 以诊断为先，不急着长篇讲解。
- 语气直接但不替学生做题。
- 每次只推进一个任务。

## 教学哲学
- 先暴露真实薄弱点，再给解释。
- 让学生为第一次尝试负责。
- 反馈必须具体、可执行，并能映射到 rubric。

## 回应习惯
- 先用一个短问题或短检查开启当前回合。
- 中途避免并行布置多个任务。
- 关键回合结尾给出 next drill 或记忆写回提示。

## 不要做
- 不要空泛鼓励。
- 不要过早给完整示范答案。
- 不要在一次回复里塞进多个模块。
"""

    return f"""# Coach Persona

## Role
{persona}

## Voice
- Lead with diagnosis instead of long lectures.
- Stay direct without taking over the learner's work.
- Keep each turn focused on one task.

## Teaching Philosophy
- Surface the real weakness before explaining.
- Keep the learner responsible for the first attempt.
- Make feedback specific, actionable, and rubric-aware.

## Response Habits
- Open with one short check or question.
- Avoid assigning multiple tasks in one turn.
- End important turns with the next drill or a memory update cue.

## Do Not Do
- Do not give empty praise.
- Do not give a full worked solution too early.
- Do not jump across multiple modules in one response.
"""


def learner_md(
    locale: str,
    document_language: str,
    coaching_language: str,
    modules: list[str],
) -> str:
    module_lines = "\n".join(
        f"- {module}: " for module in modules
    ) or "- Module 1: "

    if locale == "zh":
        return f"""# 学生画像

- 姓名:
- 学校 / 年级:
- 考试目标:
- 目标日期:
- 工作区文档语言: {document_language}
- 教练对话语言: {coaching_language}

## 各模块当前水平
{module_lines}

## 优势领域
- 

## 增长边缘
- 

## 常见错误倾向
- 

## 备注
- 
"""

    return f"""# Learner Profile

- Name:
- School / Level:
- Exam Goal:
- Target Date:
- Working Language: {document_language}
- Coaching Language: {coaching_language}

## Current Level by Module
{module_lines}

## Stronger Areas
- 

## Growth Edges
- 

## Error Tendencies
- 

## Notes
- 
"""


def memory_md(
    locale: str,
    subject: str,
    document_language: str,
    coaching_language: str,
    modules: list[str],
) -> str:
    if locale == "zh":
        module_sections = "\n\n".join(
            f"""### {module}
- 当前状态:
- 常见错误:
- 推荐下一练习:"""
            for module in modules
        ) or """### 模块 1
- 当前状态:
- 常见错误:
- 推荐下一练习:"""
        return f"""# 教练记忆

- 考试项目: {subject}
- 工作区文档语言: {document_language}
- 教练对话语言: {coaching_language}

## 学生画像快照
- 目标:
- 当前水平:
- 信心模式:

## 模块状态
{module_sections}

## 优势技能
- 

## 弱点 / 错误模式
- 

## 最近一次会话摘要
- 

## 推荐下一练习
- 
"""

    module_sections = "\n\n".join(
        f"""### {module}
- Current status:
- Common errors:
- Recommended next drill:"""
        for module in modules
    ) or """### Module 1
- Current status:
- Common errors:
- Recommended next drill:"""
    return f"""# Coaching Memory

- Exam Track: {subject}
- Workspace Language: {document_language}
- Coaching Language: {coaching_language}

## Learner Profile Snapshot
- Goal:
- Current Level:
- Confidence Pattern:

## Module Status
{module_sections}

## Stronger Skills
- 

## Weaknesses / Error Patterns
- 

## Last Session Summary
- 

## Recommended Next Drill
- 
"""


def exam_map_md(locale: str, modules: list[dict[str, str]]) -> str:
    lines: list[str] = []
    for index, module in enumerate(modules):
        prereq = "[]" if index == 0 else f"[{modules[index - 1]['slug']}]"
        lines.append(
            f"- **{module['slug']}**: prereqs={prereq} -> `topics/{module['slug']}.md`"
        )

    title = "# 训练路由" if locale == "zh" else "# Exam Map"
    return title + "\n\n" + "\n".join(lines) + "\n"


def topic_md(locale: str, subject: str, module_name: str, module_slug: str) -> str:
    if locale == "zh":
        return f"""# {module_name}

- 模块 slug: {module_slug}
- 考试项目: {subject}

## 本模块考什么
- 

## 前置依赖
- 

## 核心技能
- 

## 常见错误
- 

## 关联文件
- Rubric: `../rubrics/{module_slug}.md`
- Objectives: `../objectives/{module_slug}.md`
"""

    return f"""# {module_name}

- Module Slug: {module_slug}
- Exam Track: {subject}

## What This Module Tests
- 

## Prerequisites
- 

## Core Skills
- 

## Common Errors
- 

## Linked Files
- Rubric: `../rubrics/{module_slug}.md`
- Objectives: `../objectives/{module_slug}.md`
"""


def rubric_md(locale: str, module_name: str) -> str:
    if locale == "zh":
        return f"""# Rubric - {module_name}

## 满分信号
- 

## 扣分点
- 

## 反馈用语
- 

## 升级规则
- 如果同类错误连续出现两次，就从提示切换为显式纠正，并指出对应 rubric。
"""

    return f"""# Rubric - {module_name}

## Full-Credit Signals
- 

## Partial-Credit Losses
- 

## Feedback Phrases
- 

## Escalation Rule
- If the learner repeats the same error twice, switch from hinting to explicit correction tied to the rubric.
"""


def objectives_md(locale: str, module_name: str) -> str:
    if locale == "zh":
        return f"""# Objectives - {module_name}

## 可达成表述
- 

## 提取式检查
- 

## 晋级标准
- 
"""

    return f"""# Objectives - {module_name}

## Can-Do Statements
- 

## Retrieval Checks
- 

## Promotion Criteria
- 
"""


def session_template_md(locale: str) -> str:
    if locale == "zh":
        return """# 会话模板

- 日期:
- 聚焦模块:
- 本次目标:

## 诊断题
- 

## 学生尝试摘要
- 

## 已给反馈
- 

## 已记录错误
- 

## 下一练习
- 

## 记忆更新
- `memory/MEMORY.md` 是否更新: 是 / 否
"""

    return """# Session Template

- Date:
- Focus Module:
- Session Goal:

## Diagnostic Prompt
- 

## Learner Attempt Summary
- 

## Feedback Given
- 

## Errors Logged
- 

## Next Drill
- 

## Memory Updates
- `memory/MEMORY.md` updated: yes / no
"""


def workflow_md(locale: str, subject: str, subject_slug: str, coaching_language: str) -> str:
    if locale == "zh":
        return f"""---
description: 开始一轮 {subject} 辅导
---

# /{subject_slug} - 启动 {subject} 辅导

## 1. 载入身份
读取 `SOUL.md` 和 `AGENT.md`。

## 2. 载入学生状态
读取 `LEARNER.md` 和 `memory/MEMORY.md`。

## 3. 载入训练路由与近期记录
读取 `knowledge/exam-map.md`，并检查 `memory/sessions/` 中最近一次真实 session note。

## 4. 开始辅导
与学生对话时使用 {coaching_language}。

如果学生是回访：
- 简短提及上次暴露的弱点。
- 先做一个短复盘任务。

如果学生是新学员：
- 先问一个短诊断题。
- 把发现写回 learner 文件。
"""

    return f"""---
description: Start a coaching session for {subject}
---

# /{subject_slug} - Start {subject} Coaching

## 1. Load identity
Read `SOUL.md` and `AGENT.md`.

## 2. Load learner state
Read `LEARNER.md` and `memory/MEMORY.md`.

## 3. Load routing and recent history
Read `knowledge/exam-map.md` and check `memory/sessions/` for the most recent real session note.

## 4. Start coaching
Speak to the learner in {coaching_language}.

If the learner is returning:
- Refer briefly to the last weak point.
- Start with one short review task.

If the learner is new:
- Ask one short diagnostic question.
- Record findings in learner files.
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Initialize a reusable exam coach workspace scaffold."
    )
    parser.add_argument("workspace_path", help="Path to the workspace to create")
    parser.add_argument("--subject", required=True, help="Exam track, such as AP Calculus BC")
    parser.add_argument(
        "--document-language",
        required=True,
        help="Language used for workspace documents",
    )
    parser.add_argument(
        "--coaching-language",
        required=True,
        help="Language used when coaching the learner",
    )
    parser.add_argument("--persona", required=True, help="Coach persona summary")
    parser.add_argument(
        "--module",
        action="append",
        default=[],
        help="Module or paper name; repeat or pass a comma-separated list",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow writing into an existing non-empty directory",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    workspace = Path(args.workspace_path).expanduser().resolve()
    modules = split_modules(args.module)
    if not modules:
        print("At least one --module value is required.", file=sys.stderr)
        return 1

    locale = detect_locale(args.document_language)
    subject_slug = slugify(args.subject)
    module_specs = build_module_specs(modules)

    try:
        ensure_empty_or_new(workspace, args.force)
    except FileExistsError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    workspace.mkdir(parents=True, exist_ok=True)
    mkdirs(workspace)

    write_text(workspace / "AGENT.md", agent_md(locale, args.subject, args.coaching_language))
    write_text(workspace / "SOUL.md", soul_md(locale, args.persona))
    write_text(
        workspace / "LEARNER.md",
        learner_md(
            locale,
            args.document_language,
            args.coaching_language,
            modules,
        ),
    )
    write_text(
        workspace / "memory/MEMORY.md",
        memory_md(
            locale,
            args.subject,
            args.document_language,
            args.coaching_language,
            modules,
        ),
    )
    write_text(workspace / "knowledge/exam-map.md", exam_map_md(locale, module_specs))
    write_text(
        workspace / "memory/sessions/_template.md",
        session_template_md(locale),
    )
    write_text(
        workspace / f".agent/workflows/{subject_slug}.md",
        workflow_md(locale, args.subject, subject_slug, args.coaching_language),
    )

    for module in module_specs:
        write_text(
            workspace / f"knowledge/topics/{module['slug']}.md",
            topic_md(locale, args.subject, module["name"], module["slug"]),
        )
        write_text(
            workspace / f"knowledge/rubrics/{module['slug']}.md",
            rubric_md(locale, module["name"]),
        )
        write_text(
            workspace / f"knowledge/objectives/{module['slug']}.md",
            objectives_md(locale, module["name"]),
        )

    print(f"Initialized workspace: {workspace}")
    print(f"Subject slug: {subject_slug}")
    print(f"Document locale used for templates: {locale}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
