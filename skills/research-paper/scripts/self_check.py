#!/usr/bin/env python3
"""
Lightweight validation for the research-paper skill.
Checks packaging, stale instruction patterns, and a few key workflow contracts.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
SYSTEM_SKILL_CREATOR = Path("/home/caesar/.codex/skills/.system/skill-creator")
QUICK_VALIDATE = SYSTEM_SKILL_CREATOR / "scripts" / "quick_validate.py"


def run_quick_validate(issues: list[str]) -> None:
    result = subprocess.run(
        [sys.executable, str(QUICK_VALIDATE), str(ROOT)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        issues.append(f"quick_validate failed: {result.stdout.strip() or result.stderr.strip()}")


def require_file(path: Path, issues: list[str]) -> None:
    if not path.exists():
        issues.append(f"missing file: {path.relative_to(ROOT)}")


def read_text(path: Path, issues: list[str]) -> str:
    try:
        return path.read_text()
    except FileNotFoundError:
        issues.append(f"missing file: {path.relative_to(ROOT)}")
        return ""


def check_openai_yaml(issues: list[str]) -> None:
    path = ROOT / "agents" / "openai.yaml"
    require_file(path, issues)
    if not path.exists():
        return

    data = yaml.safe_load(path.read_text()) or {}
    interface = data.get("interface", {})

    if interface.get("display_name") != "Political Science Research Paper":
        issues.append("agents/openai.yaml has an unexpected display_name")

    short_description = interface.get("short_description", "")
    if not (25 <= len(short_description) <= 64):
        issues.append("agents/openai.yaml short_description must be 25-64 characters")

    prompt = interface.get("default_prompt", "")
    if "$research-paper" not in prompt:
        issues.append("agents/openai.yaml default_prompt must mention $research-paper")


def check_legacy_patterns(issues: list[str]) -> None:
    skill_text = read_text(ROOT / "SKILL.md", issues)
    if 'message="读取 skill/<文件>.md 执行 <Agent>"' in skill_text or "读取 skill/<文件>.md 执行 <Agent>" in skill_text:
        issues.append("SKILL.md still contains the legacy skill/<文件>.md path")
    if "使用 Read tool" in skill_text:
        issues.append("SKILL.md still references a non-existent Read tool")

    legacy_tool_line = re.compile(r"^\*\*工具:\*\* .*?\b(Read|Write|Edit|webfetch)\b", re.MULTILINE)
    for relative in ("planning.md", "writing.md", "review.md"):
        text = read_text(ROOT / relative, issues)
        if legacy_tool_line.search(text):
            issues.append(f"{relative} still contains legacy tool names in a tool declaration")


def check_workflow_contracts(issues: list[str]) -> None:
    skill_text = read_text(ROOT / "SKILL.md", issues)
    writing_text = read_text(ROOT / "writing.md", issues)
    review_text = read_text(ROOT / "review.md", issues)

    required_skill_snippets = [
        "causal_mechanism.md（若存在）",
        "本轮未做过程追踪证据评估",
        "所有章节文件 + literature_review.md（推荐） + historical_context.md（如需补齐出处）",
    ]
    for snippet in required_skill_snippets:
        if snippet not in skill_text:
            issues.append(f"SKILL.md is missing required workflow snippet: {snippet}")

    required_writing_snippets = [
        "causal_mechanism.md`（可选）",
        "无过程追踪时的降级路径",
        "禁止编造",
    ]
    for snippet in required_writing_snippets:
        if snippet not in writing_text:
            issues.append(f"writing.md is missing required workflow snippet: {snippet}")

    required_review_snippets = [
        "本轮未做过程追踪",
        "真实性抽检",
        "已有审查报告（5 份或 6 份）",
    ]
    for snippet in required_review_snippets:
        if snippet not in review_text:
            issues.append(f"review.md is missing required workflow snippet: {snippet}")


def main() -> int:
    issues: list[str] = []

    run_quick_validate(issues)

    for relative in [
        "SKILL.md",
        "planning.md",
        "writing.md",
        "review.md",
        "references/analytic-narratives.md",
        "references/process-tracing.md",
        "references/caltech-rules.md",
        "agents/openai.yaml",
    ]:
        require_file(ROOT / relative, issues)

    check_openai_yaml(issues)
    check_legacy_patterns(issues)
    check_workflow_contracts(issues)

    if issues:
        print("research-paper self-check: FAILED")
        for issue in issues:
            print(f"- {issue}")
        return 1

    print("research-paper self-check: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
