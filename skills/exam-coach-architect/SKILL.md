---
name: exam-coach-architect
description: 构建或刷新一个基于 Markdown 驱动、动静分离、带长期记忆和会话工作流的应试教练工作区。适用于任何需要按考试模块、评分标准和知识地图进行微步辅导的科目，例如 AP Calculus、SAT Math、IB Economics、IELTS Speaking。用户想为某个考试科目创建可复用的教练目录、Persona、Learner 状态、记忆文件、训练路由或 slash/workflow 启动文件时使用。
---

# Exam Coach Architect

你是在为另一个 Codex 实例搭建长期可复用的教练工作区，而不是临时回答一道题。

按需读取以下文件，不要一次性全读：

- `references/interview-checklist.md`：缺信息时用的访谈清单与默认假设规则
- `references/workspace-layout.md`：标准目录、命名规范与输出路径约束
- `references/core-file-templates.md`：`AGENT.md`、`SOUL.md`、`LEARNER.md`、`memory/MEMORY.md` 模板
- `references/routing-and-session-templates.md`：`knowledge/exam-map.md`、模块子文件、session 模板、workflow 模板

## 核心规则

1. 全程使用用户当前对话语言与用户沟通，除非用户另有要求。
2. 绝不要把用户工件写进本 skill 目录，或任何明显属于 `.../skills/...` 的目录。
3. 只询问缺失的关键信息；已提供的信息直接复用。
4. 输出目录如果已存在且会覆盖现有文件，不要静默覆盖；先停下并让用户确认，或改用新的时间戳目录。
5. 明确区分两种语言：`工作区文档语言` 和 `未来教练与学生的交互语言`。不要混为一谈。
6. 所有生成内容都要围绕“长期辅导”而不是“一次性答题”，必须包含记忆写回与会话归档。
7. 不要假装已经导入 syllabus、rubric 或 past papers。没有源材料时，只生成清晰的空壳与待填字段。

## 必需输入

缺失或歧义时，读取 `references/interview-checklist.md` 并只补问最关键的问题。最低必需输入为：

- 科目与考试体系
- 输出目录或工作区根目录
- 工作区文档语言
- 教练与学生的交互语言
- 主要考核模块 / 题型 / paper 列表
- 教练人格设定

可选但推荐：

- 学生目标分数或目标等级
- 当前水平
- 默认训练节奏

## 执行流程

### 1. 收集并标准化输入

- 为科目生成稳定 slug，使用小写连字符形式，例如 `ap-calculus-bc`。
- 将模块列表标准化为“展示名 + slug”，例如 `Paper 1 (MCQ)` -> `paper-1-mcq`。
- 如果用户没有给模块，但考试结构高度标准化且低风险，可以先提出一个 provisional 列表并明确说明是暂定值。

### 2. 选择安全的输出目录

先读取 `references/workspace-layout.md`。

- 优先使用用户明确指定的目标目录。
- 如果当前 `cwd` 指向 skill 目录、`.../skills/...` 路径或其他明显不适合存放用户工件的目录，不要在此写入；改为要求用户指定工作区根目录。
- 如果当前目录安全且用户未指定目标目录，则创建 `runs/YYYY-MM-DD-<subject-slug>/`。

### 3. 创建目录脚手架

优先使用初始化脚本，而不是手工逐个建空文件：

```bash
python3 scripts/init_exam_coach_workspace.py <workspace-path> \
  --subject "<subject>" \
  --document-language "<document-language>" \
  --coaching-language "<coaching-language>" \
  --persona "<persona>" \
  --module "<module-1>" \
  --module "<module-2>"
```

约定：

- 对中文或英文工作区，脚本会直接生成可用初稿。
- 对其他工作区文档语言，先用脚本生成稳定骨架，再按 `references/*.md` 模板把可见文字翻译到目标语言。
- 只有在脚本不适用或用户明确要求完全定制时，才手工逐文件生成。

在目标目录下创建以下结构：

```text
knowledge/topics
knowledge/rubrics
knowledge/objectives
knowledge/examples
memory/sessions
sources/past-papers
.agent/workflows
```

### 4. 生成核心文件

先读取 `references/core-file-templates.md`，并按所选工作区文档语言生成：

- `AGENT.md`
- `SOUL.md`
- `LEARNER.md`
- `memory/MEMORY.md`

强制要求：

- `AGENT.md` 必须显式写出：先诊断再教学、学生先尝试、rubric 关联反馈、每轮只推进一个任务、关键练习后写记忆。
- `SOUL.md` 必须把用户的人格设定落实为 voice、teaching philosophy、response habits、do-not-do。
- `memory/MEMORY.md` 的状态区必须按标准化后的模块逐项展开，不能只写一句“待填写”。

### 5. 生成训练路由、模块骨架与会话工作流

再读取 `references/routing-and-session-templates.md`，生成：

- `knowledge/exam-map.md`
- `memory/sessions/_template.md`
- `.agent/workflows/<subject-slug>.md`

并且为每个模块至少生成一组三件套：

- `knowledge/topics/<module-slug>.md`
- `knowledge/rubrics/<module-slug>.md`
- `knowledge/objectives/<module-slug>.md`

要求：

- `knowledge/exam-map.md` 中出现的每个 `topics/...md` 路径都必须真实存在。
- workflow 文件必须使用标准化后的科目 slug，并明确载入 `SOUL.md`、`AGENT.md`、`LEARNER.md`、`memory/MEMORY.md` 和最近一次 session note。
- 如果还没有真题或范文，不要伪造 `knowledge/examples/` 内容。

### 6. 校验

生成完成后，运行：

```bash
python3 scripts/validate_exam_coach_workspace.py <workspace-path>
```

修复所有报错后再交付。若无法运行脚本，至少手动检查以下事项：

- 必需目录和文件都存在
- `exam-map` 里的路径不悬空
- 每个模块都有 topic / rubric / objective 文件
- workflow 文件名与科目 slug 一致
- 文档语言与交互语言没有混淆

### 7. 交付

向用户汇报时只说高信号内容：

1. 工作区创建在什么路径
2. 生成了哪些关键控制文件
3. 如何通过 `/.agent/workflows/<subject-slug>.md` 对应的命令启动首次会话
4. 在第一次正式辅导前，建议先 `git init` 并提交一次初始快照
5. 下一步最值得补充的材料是什么，例如 rubric、syllabus、past papers

## 不要做的事

- 不要把输出写进 skill 目录
- 不要静默覆盖已有工作区
- 不要把“文档语言”和“教练对话语言”写成同一个字段却表达不同含义
- 不要在 `exam-map` 里放不存在的文件引用
- 不要生成看起来很满但其实不可执行的空泛内容
