---
name: hda
description: "Analyze the historical evolution and structural logic of a bounded industry, technology, institution, cultural form, business model, product category, or object. Use when the user wants more than a timeline: phased evolution, paradigm-shifting turning points, key actors, and the underlying pattern of change. Best for questions such as how X evolved or what changed X's trajectory; not for pure biography, single-event recap, present-day tactical recommendations, or very broad civilizational abstractions unless the answer first narrows scope."
metadata:
  short-description: "Panoramic historical-structural analysis"
---

# Holistic Domain Analyst

Build a panoramic history of a subject, not a chronology dump.

## Use This Skill For

- Historical analysis of an industry, technology, platform, institution, standard, genre, product category, or social practice
- Questions that ask how a subject evolved, what changed its trajectory, or what deep pattern explains its development
- Answers that need periodization, turning points, key actors, and structural interpretation in one frame
- Bounded subjects with a traceable historical trajectory, rather than unlimited abstractions

If the request is mainly a biography, a single event recap, or a present-day tactical recommendation, do not force this skill onto the whole answer. Use HDA only for the historical subsection, or answer directly.

If the subject is civilization-scale or highly abstract, such as "AI", "capitalism", or "democracy", narrow it before applying HDA. Pick one unit of analysis, one geography, and one tractable historical window, then say so explicitly.

## Workflow

1. Scope the subject.
2. Gather dated evidence.
3. Build the four-dimensional map.
4. State uncertainty, contested interpretations, or boundary choices explicitly.

Read [references/scoping.md](references/scoping.md) when the subject boundary or phase design is unclear.

Read [references/evidence.md](references/evidence.md) when you need sourcing rules, browsing guidance, or confidence framing.

Read one of the example files when you want a concrete model for tone and granularity:

- [examples/semiconductor-industry.md](examples/semiconductor-industry.md) for technology and industrial systems
- [examples/streaming-video.md](examples/streaming-video.md) for platforms and business-model shifts
- [examples/coffee.md](examples/coffee.md) for commodity history, consumer culture, and symbolic upgrading

## Boundary Cases

- Pure biography or one-off event: do not force the four-dimension structure.
- Product recommendation, investment advice, or present-day tactical choice: answer directly, and use HDA only if the user explicitly asks for historical background.
- "Why did one company or platform rise?" questions are partial-fit cases. Answer the immediate causal question first, then use HDA only if a multi-phase historical buildup materially improves the explanation.
- If the subject is too broad to cover responsibly, narrow it instead of pretending a complete panoramic map is possible.

## Step 1: Scope the Subject

Start by identifying four things:

- Unit of analysis: what exactly is being traced
- Time range: explicit or implied historical window
- Geography: global, regional, or country-specific path
- Primary lens: technology, market structure, regulation, culture, organization, or infrastructure

If the user leaves one of these unspecified and it materially changes the answer, make a reasonable assumption and state it near the beginning.

If the original prompt is too broad, narrow in this order:

- Pick the real unit of analysis
- Pick the dominant geography
- Pick the historical window where the rules of the game were formed

## Step 2: Gather Evidence

Prioritize evidence that changed one or more of the following:

- Capability: what could be built or produced
- Incentives: how firms, states, creators, or users made decisions
- Legitimacy: how the subject was classified, accepted, or regulated
- Scale: who could access it, at what cost, and through what channels

Do not invent names, dates, or causal claims. If the topic involves recent developments, precise source attribution, regulation, or user-requested verification, browse and verify before answering.

## Step 3: Produce the Four Dimensions

### 1. Evolutionary Phases

Usually divide the subject into 3-5 named phases. For each phase, include:

- Phase name plus rough years
- The transition: what it moved from and what it moved toward
- 2-4 defining characteristics

Avoid arbitrary decade slicing. Phase boundaries should be justified by a real change in dominant technology, market structure, regulation, user base, or cultural meaning.

### 2. Critical Inflection Points

Identify 3-5 game-changing events. Use the format:

- `[year or date] event name: why the rules changed`

Only include paradigm-shift events, not routine milestones. Good candidates include technological breakthroughs, standard-setting moments, major regulatory changes, infrastructure shifts, or business-model resets.

### 3. Architects

Identify 4-6 actors who changed the trajectory of the subject. Do not default to a list of CEOs or politicians. Aim to cover multiple roles such as:

- Rule maker
- Technical inventor
- Organizational builder
- Cultural evangelist
- Financier, distributor, or platform gatekeeper

Use the format:

- `[person or organization] + [identity] + [mechanism of influence]`

If an institution or organization mattered more than any individual person, it is acceptable to name the institution.

### 4. Core Narrative

End with one compact paragraph or one strong thesis sentence that states the deepest pattern of change. Good narrative arcs often look like:

- Scarcity to abundance
- Elite control to mass access
- Fragmentation to standardization
- National systems to global platforms
- Functionality to identity and symbolism

The point is not to force one of these arcs, but to name the real structural movement.

## Output Rules

- Default to Chinese unless the user requests another language.
- Lead with a 1-2 sentence thesis, then present the four dimensions.
- If the user wants a brief answer, compress each dimension rather than dropping dimensions entirely.
- If evidence is thin, disputed, or region-specific, add a short confidence note.
- If useful, add a final section on "what this historical pattern implies now", but keep it separate from the historical narrative.
