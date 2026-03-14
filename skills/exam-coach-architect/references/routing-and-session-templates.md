# 路由与会话模板

保持结构稳定；将可见文字翻译为工作区文档语言。所有示例路径都要替换为真实模块 slug。

## `knowledge/exam-map.md`

```markdown
# Exam Map

- **{{module_slug_1}}**: prereqs=[] -> `topics/{{module_slug_1}}.md`
- **{{module_slug_2}}**: prereqs=[{{module_slug_1}}] -> `topics/{{module_slug_2}}.md`
```

如果模块之间没有明显前置关系，也要明确写成 `prereqs=[]`，不要留成模糊描述。

## `knowledge/topics/<module-slug>.md`

```markdown
# {{module_name}}

- Module Slug: {{module_slug}}
- Exam Track: {{subject}}

## What This Module Tests
- 

## Prerequisites
- 

## Core Skills
- 

## Common Errors
- 

## Linked Files
- Rubric: `../rubrics/{{module_slug}}.md`
- Objectives: `../objectives/{{module_slug}}.md`
```

## `knowledge/rubrics/<module-slug>.md`

```markdown
# Rubric - {{module_name}}

## Full-Credit Signals
- 

## Partial-Credit Losses
- 

## Feedback Phrases
- 

## Escalation Rule
- If the learner repeats the same error twice, switch from hinting to explicit correction tied to the rubric.
```

## `knowledge/objectives/<module-slug>.md`

```markdown
# Objectives - {{module_name}}

## Can-Do Statements
- 

## Retrieval Checks
- 

## Promotion Criteria
- 
```

## `memory/sessions/_template.md`

```markdown
# Session Template

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
```

## `.agent/workflows/<subject-slug>.md`

```markdown
---
description: Start a coaching session for {{subject}}
---

# /{{subject_slug}} - Start {{subject}} Coaching

## 1. Load identity
Read `SOUL.md` and `AGENT.md`.

## 2. Load learner state
Read `LEARNER.md` and `memory/MEMORY.md`.

## 3. Load routing and recent history
Read `knowledge/exam-map.md` and check `memory/sessions/` for the most recent real session note.

## 4. Start coaching
Speak to the learner in {{coaching_language}}.

If the learner is returning:
- Refer briefly to the last weak point.
- Start with one short review task.

If the learner is new:
- Ask one short diagnostic question.
- Record findings in learner files.
```
