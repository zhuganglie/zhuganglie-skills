---
name: hda
description: "Analyze how a bounded industry, technology, institution, cultural form, business model, product category, or object evolved over time. Use when the user wants named phases, paradigm-shifting turning points, key actors, and the underlying structural pattern. Do not use for pure biography, single events, most single-company rise questions, present-day tactical recommendations, or civilization-scale abstractions unless you first narrow the scope."
metadata:
  short-description: "Panoramic historical-structural analysis"
---

# Holistic Domain Analyst

<purpose>
Build a panoramic history of a subject, not a chronology dump.
</purpose>

<use_cases>
## Use This Skill For
- Historical analysis of an industry, technology, platform, institution, standard, genre, product category, or social practice.
- Questions that ask how a subject evolved, what changed its trajectory, or what deep pattern explains its development.
- Answers that need periodization, turning points, key actors, and structural interpretation in one frame.
- Bounded subjects with a traceable historical trajectory, rather than unlimited abstractions.

## Boundary Cases & Quick Fit Test
Use full HDA **only** when both are true:
1. The subject is a bounded domain or category with a multi-phase trajectory.
2. The user wants a historical-structural explanation, not just the immediate cause of one outcome.

- **Broad Subjects:** If the subject is civilization-scale or highly abstract ("AI", "capitalism", "democracy"), narrow it before applying HDA. Pick one unit of analysis, one geography, and one tractable historical window, then explicitly state it.
- **Partial Fits:** If the request is mainly a biography, a single event recap, a present-day tactical recommendation, or a "Why did one company rise?" question, **do not** force the full four-dimension structure. Answer the immediate question directly first, and use HDA only for the historical background subsection if it materially improves the explanation.
</use_cases>

<workflow>
1. Scope the subject.
2. Gather dated evidence (use search tools if necessary).
3. Build the four-dimensional map.
4. State uncertainty, contested interpretations, or boundary choices explicitly.

## Step 1: Scope the Subject
Start by identifying four things:
- **Unit of analysis:** what exactly is being traced
- **Time range:** explicit or implied historical window
- **Geography:** global, regional, or country-specific path
- **Primary lens:** technology, market structure, regulation, culture, organization, or infrastructure

If the original prompt is too broad, narrow in this order:
1. Pick the real unit of analysis
2. Pick the dominant geography
3. Pick the historical window where the rules of the game were formed

*If you had to choose or assume the unit, geography, time window, or primary lens yourself, you MUST surface that choice in a one-line `【研究范围】` (Scope) note right after the opening thesis.*

## Step 2: Gather Evidence
Prioritize evidence that changed one or more of the following:
- **Capability:** what could be built or produced
- **Incentives:** how firms, states, creators, or users made decisions
- **Legitimacy:** how the subject was classified, accepted, or regulated
- **Scale:** who could access it, at what cost, and through what channels

**Do not invent names, dates, or causal claims.** Use your web search tools (e.g., `google_search`, `webfetch`) to gather and verify precise source attribution, regulation details, or recent developments before answering.

## Step 3: Produce the Four Dimensions

### 1. Evolutionary Phases (演进阶段)
Usually divide the subject into 3-5 named phases. Avoid arbitrary decade slicing. Boundaries should be justified by a real change in dominant technology, market structure, regulation, user base, or cultural meaning. For each phase, include:
- Phase name plus rough years
- The transition: what it moved from and what it moved toward
- 2-4 defining characteristics

### 2. Critical Inflection Points (关键拐点)
Identify 3-5 game-changing events (paradigm-shift events, not routine milestones). Use this format:
- `[年份/日期] 事件名称：规则改变的原因 (why the rules changed)`

### 3. Architects (核心推手)
Identify 4-6 actors (individuals or institutions) who changed the trajectory of the subject. Aim to cover multiple roles (Rule maker, Technical inventor, Organizational builder, Cultural evangelist, Platform gatekeeper). Use this format:
- `[人物或机构名称] + [身份角色] + [影响机制 (mechanism of influence)]`

### 4. Core Narrative (核心论点与深层模式)
Identify one strong thesis sentence that states the deepest pattern of change (e.g., Scarcity to abundance, Elite control to mass access, Fragmentation to standardization, Functionality to identity).
</workflow>

<references>
- Read [references/scoping.md](references/scoping.md) when the subject boundary or phase design is unclear.
- Read [references/evidence.md](references/evidence.md) when you need sourcing rules, browsing guidance, or confidence framing.
- Read example files for tone and granularity:
  - [examples/semiconductor-industry.md](examples/semiconductor-industry.md) (technology and industrial systems)
  - [examples/streaming-video.md](examples/streaming-video.md) (platforms and business-model shifts)
  - [examples/coffee.md](examples/coffee.md) (commodity history, consumer culture)
  - [examples/netflix-vs-blockbuster.md](examples/netflix-vs-blockbuster.md) (partial-fit case)
</references>

<output_rules>
- Default to Chinese unless the user requests another language.
- Lead with a 1-2 sentence thesis, followed by the scope note (if applicable), then present the four dimensions.
- If the user wants a brief answer, compress each dimension rather than dropping dimensions entirely.
- If evidence is thin, disputed, region-specific, or your phase or architect choices are interpretive, add a short `【置信度与边界声明】` note at the end.
- If useful, add a final section on "what this historical pattern implies now", but keep it separate from the historical narrative.
- Strictly follow the `<output_template>` structure below.
</output_rules>

<output_template>
# [主题名称] 的历史演进与结构分析

**核心论点：** [1-2句话概述最深层的变革模式，例如：从稀缺走向富足、从去中心化走向平台垄断等]

**【研究范围】：** [仅当由AI自行假设或收窄时提供：分析单元、地理范围、时间窗口或主要视角]

## 一、 演进阶段 (Evolutionary Phases)
[阶段一：名称] (年份 - 年份)
- **转型动力：** [从X演变为Y]
- **核心特征：** 
  - [特征1]
  - [特征2]

[阶段二：名称] (年份 - 年份)
...

## 二、 关键拐点 (Critical Inflection Points)
- **[年份] [事件名称]：** [详细说明规则为何改变]
- **[年份] [事件名称]：** [详细说明规则为何改变]
...

## 三、 核心推手 (Architects)
- **[人物/机构名称] ([身份角色])：** [具体的影响机制，他们如何改变了轨迹]
- **[人物/机构名称] ([身份角色])：** [具体的影响机制，他们如何改变了轨迹]
...

## 四、 深层模式与当下启示 (Deep Pattern & Implications)
[总结这段历史反映出的深层结构规律，以及这些历史规律对当下的启示或对未来的预测]

---
**【置信度与边界声明】：** [仅在证据不足、存在争议或解释带有主观选择性时添加说明]
</output_template>