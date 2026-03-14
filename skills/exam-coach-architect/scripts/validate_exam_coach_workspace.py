#!/usr/bin/env python3

import argparse
import re
import sys
from pathlib import Path


REQUIRED_DIRS = [
    "knowledge/topics",
    "knowledge/rubrics",
    "knowledge/objectives",
    "knowledge/examples",
    "memory/sessions",
    "sources/past-papers",
    ".agent/workflows",
]

REQUIRED_FILES = [
    "AGENT.md",
    "SOUL.md",
    "LEARNER.md",
    "memory/MEMORY.md",
    "knowledge/exam-map.md",
    "memory/sessions/_template.md",
]


def collect_errors(workspace: Path) -> list[str]:
    errors: list[str] = []

    for rel_path in REQUIRED_DIRS:
        path = workspace / rel_path
        if not path.is_dir():
            errors.append(f"Missing directory: {rel_path}")

    for rel_path in REQUIRED_FILES:
        path = workspace / rel_path
        if not path.is_file():
            errors.append(f"Missing file: {rel_path}")

    workflows_dir = workspace / ".agent/workflows"
    workflow_files = sorted(workflows_dir.glob("*.md")) if workflows_dir.is_dir() else []
    if not workflow_files:
        errors.append("Missing workflow file in .agent/workflows/")

    topics_dir = workspace / "knowledge/topics"
    rubrics_dir = workspace / "knowledge/rubrics"
    objectives_dir = workspace / "knowledge/objectives"

    topic_files = sorted(topics_dir.glob("*.md")) if topics_dir.is_dir() else []
    rubric_files = sorted(rubrics_dir.glob("*.md")) if rubrics_dir.is_dir() else []
    objective_files = sorted(objectives_dir.glob("*.md")) if objectives_dir.is_dir() else []

    if not topic_files:
        errors.append("No topic files found in knowledge/topics/")
    if not rubric_files:
        errors.append("No rubric files found in knowledge/rubrics/")
    if not objective_files:
        errors.append("No objective files found in knowledge/objectives/")

    exam_map = workspace / "knowledge/exam-map.md"
    if exam_map.is_file():
        refs = re.findall(r"`([^`]+\.md)`", exam_map.read_text(encoding="utf-8"))
        if not refs:
            errors.append("knowledge/exam-map.md does not reference any markdown files")
        for ref in refs:
            ref_path = Path(ref)
            candidate = ref_path if ref_path.is_absolute() else workspace / "knowledge" / ref_path
            if not candidate.is_file():
                errors.append(f"Broken exam-map reference: {ref}")

    for workflow_file in workflow_files:
        text = workflow_file.read_text(encoding="utf-8")
        for required_ref in ("SOUL.md", "AGENT.md", "LEARNER.md", "memory/MEMORY.md"):
            if required_ref not in text:
                errors.append(
                    f"Workflow file {workflow_file.name} does not mention {required_ref}"
                )

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate an exam coach workspace scaffold."
    )
    parser.add_argument("workspace_path", help="Path to the generated workspace")
    args = parser.parse_args()

    workspace = Path(args.workspace_path).expanduser().resolve()
    if not workspace.exists():
        print(f"Workspace does not exist: {workspace}", file=sys.stderr)
        return 1

    errors = collect_errors(workspace)
    if errors:
        print("Workspace validation failed:")
        for error in errors:
            print(f"- {error}")
        return 1

    print(f"Workspace validation passed: {workspace}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
