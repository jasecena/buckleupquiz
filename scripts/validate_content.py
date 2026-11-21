#!/usr/bin/env python3
"""Validate the BuckleUp Quiz content bank (FEATURES §4.2, ADR-0006).

Checks the topic catalogue and every question file for schema errors, duplicate ids,
free-answer ("open") questions, answers that are not one of the options, and questions
that take too long to read aloud (options included). Prints a coverage table against the launch targets.

Usage:
    python3 scripts/validate_content.py [--content Content] [--strict] [--json]

Exit code 1 if any error is found. Warnings never fail the build unless --strict,
which also enforces the launch content targets (use it for release builds).
Standard library only, so it runs anywhere without installing anything.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

AGE_BANDS = ("6-8", "9-10", "11-12")
BAND_AGES = {"6-8": (6, 8), "9-10": (9, 10), "11-12": (11, 12)}
TYPES = ("multipleChoice", "trueFalse", "talkAbout")  # quiz questions are a choice (ADR-0015)
CHOICE_OPTIONS = 3  # every multiple-choice question has exactly three options
CATEGORIES = ("knowledge", "values", "safety")
ID_PATTERN = re.compile(r"^[a-z]{3}-\d{4}$")
HEX_COLOUR = re.compile(r"^#[0-9A-Fa-f]{6}$")

# Speaking-time estimate: AVSpeechSynthesizer at the kid-friendly default rate reads
# roughly 2.5 words per second. Questions (plus read-aloud options) must fit in 12 s.
WORDS_PER_SECOND = 2.5
MAX_SPEAK_SECONDS = 12.0
MAX_ANSWER_WORDS = 4

# Launch targets (FEATURES §4.2 and §4.3).
TARGET_PER_BAND = 60
MANNERS_SCORED_PER_BAND = 40
MANNERS_TALK_PER_BAND = 20

# Words that should never appear in values/safety content (FEATURES §4.3, §4.5, §4.6).
BANNED_IN_VALUES = ("stupid", "idiot", "dumb", "loser", "stranger danger", "ugly", "fat", "diet")

ARTICLES = {"the", "a", "an"}


# Options that lean on the question ("Wait for someone else to do it": do what?).
VAGUE_OPTION = re.compile(r"\b(do|does|did|doing) (it|that|this|so)\b|\b(it|that) (first|around|again)\b", re.IGNORECASE)


def normalise(text: str) -> str:
    """Rough mirror of TextNormalizer.normalize (without number-word conversion)."""
    text = unicodedata.normalize("NFKD", text)
    text = "".join(c for c in text if not unicodedata.combining(c)).lower()
    text = re.sub(r"['’‘`]", "", text)
    text = re.sub(r"[^a-z0-9.]+", " ", text)
    return " ".join(t for t in text.split() if t not in ARTICLES)


def word_count(text: str) -> int:
    return len(re.findall(r"[\w'’-]+", text))


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, where: str, message: str) -> None:
        self.errors.append(f"{where}: {message}")

    def warn(self, where: str, message: str) -> None:
        self.warnings.append(f"{where}: {message}")


def load_json(path: Path, report: Report):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        report.error(str(path), f"cannot read JSON ({exc})")
        return None


def validate_topics(topics, report: Report) -> dict[str, dict]:
    where = "topics.json"
    if not isinstance(topics, list):
        report.error(where, "must be an array of topics")
        return {}
    by_id: dict[str, dict] = {}
    required = {"id": str, "name": str, "symbol": str, "color": str, "category": str,
                "isFree": bool, "ageBands": list, "requiresReview": bool}
    for i, t in enumerate(topics):
        tw = f"{where}[{i}]"
        if not isinstance(t, dict):
            report.error(tw, "must be an object")
            continue
        for key, kind in required.items():
            if not isinstance(t.get(key), kind):
                report.error(tw, f"'{key}' must be {kind.__name__}")
        tid = t.get("id")
        if isinstance(tid, str):
            tw = f"{where}:{tid}"
            if tid in by_id:
                report.error(tw, "duplicate topic id")
            by_id[tid] = t
        if isinstance(t.get("color"), str) and not HEX_COLOUR.match(t["color"]):
            report.error(tw, "color must look like #RRGGBB")
        if t.get("category") not in CATEGORIES:
            report.error(tw, f"category must be one of {CATEGORIES}")
        for band in t.get("ageBands") or []:
            if band not in AGE_BANDS:
                report.error(tw, f"unknown age band {band!r}")
    free = [tid for tid, t in by_id.items() if t.get("isFree")]
    if len(free) != 3:
        report.warn(where, f"FEATURES §2.1 expects 3 free topics, found {len(free)}: {free}")
    return by_id


def validate_question(q, where: str, topics: dict[str, dict], report: Report) -> None:
    if not isinstance(q, dict):
        report.error(where, "question must be an object")
        return
    for key in ("id", "topic", "ageBand", "type", "question"):
        if not isinstance(q.get(key), str) or not q[key].strip():
            report.error(where, f"'{key}' is required and must be a non-empty string")
    qid, qtype, band = q.get("id", ""), q.get("type"), q.get("ageBand")
    if isinstance(qid, str) and not ID_PATTERN.match(qid):
        report.error(where, "id must look like 'abc-0001'")
    if qtype == "open":
        report.error(where, "open quiz questions are not allowed (ADR-0015). Use multipleChoice with "
                            "3 options or trueFalse; open discussion questions are talkAbout")
        return
    if qtype == "scenario":
        report.error(where, "'scenario' was merged into multipleChoice (ADR-0015); change the type")
        return
    if qtype not in TYPES:
        report.error(where, f"type must be one of {TYPES}")
        return
    if band not in AGE_BANDS:
        report.error(where, f"ageBand must be one of {AGE_BANDS}")
        return

    topic = topics.get(q.get("topic"))
    if topic is None:
        report.error(where, f"unknown topic {q.get('topic')!r}")
    elif band not in topic.get("ageBands", []):
        report.error(where, f"topic {topic['id']} has no {band} band")

    options, answer = q.get("options"), q.get("answer")
    accepted = q.get("acceptedAnswers", [])
    if not isinstance(accepted, list) or not all(isinstance(a, str) and a.strip() for a in accepted):
        report.error(where, "acceptedAnswers must be a list of non-empty strings")
        accepted = []

    difficulty = q.get("difficulty", 1)
    if not isinstance(difficulty, int) or not 1 <= difficulty <= 5:
        report.error(where, "difficulty must be an integer 1-5")
    min_age = q.get("minAge")
    if min_age is not None:
        low, high = BAND_AGES[band]
        if not isinstance(min_age, int) or not low <= min_age <= high:
            report.error(where, f"minAge must be within the {band} band ({low}-{high})")
    for key in ("funFact", "explanation", "region"):
        if q.get(key) is not None and not isinstance(q[key], str):
            report.error(where, f"'{key}' must be a string or null")

    # Type-specific rules.
    if qtype == "talkAbout":
        if answer is not None or options is not None or accepted:
            report.error(where, "talkAbout prompts have no answer, options or acceptedAnswers")
    else:
        if not isinstance(answer, str) or not answer.strip():
            report.error(where, "answer is required for scored questions")
            return
    if qtype == "multipleChoice":
        if not isinstance(options, list) or len(options) != CHOICE_OPTIONS \
                or not all(isinstance(o, str) and o.strip() for o in options):
            report.error(where, f"multipleChoice needs exactly {CHOICE_OPTIONS} non-empty options")
        else:
            normalised = [normalise(o) for o in options]
            if len(set(normalised)) != len(normalised):
                report.error(where, "options must be distinct")
            if normalise(answer) not in normalised:
                report.error(where, "answer must be one of the options")
            if any(len(normalise(a)) == 1 for a in accepted):
                report.error(where, "don't put option letters in acceptedAnswers; options are shuffled")
            category = (topics.get(q.get("topic")) or {}).get("category")
            for o in options:
                # Each option is read out on its own ("The best choice is… B: …"), so it must
                # make sense without the question: name the action, not "do it".
                if VAGUE_OPTION.search(o):
                    report.error(where, f"option '{o}' doesn't stand on its own; say what to do instead of 'do it'")
                # Values/safety options describe an action, so they may be a short phrase.
                if category == "knowledge" and word_count(o) > MAX_ANSWER_WORDS:
                    report.warn(where, f"option '{o}' has more than {MAX_ANSWER_WORDS} words; keep options easy to say")
    elif qtype == "trueFalse":
        if options is not None:
            report.error(where, "trueFalse questions must not set options")
        if answer not in ("True", "False"):
            report.error(where, "trueFalse answer must be 'True' or 'False'")
        if "true or false" not in q["question"].lower():
            report.warn(where, "trueFalse questions should end with 'True or false?'")

    # Read-aloud length (question + options as spoken).
    spoken = q["question"] + (" " + " ".join(options) if isinstance(options, list) else "")
    seconds = word_count(spoken) / WORDS_PER_SECOND
    if seconds > MAX_SPEAK_SECONDS:
        report.error(where, f"takes about {seconds:.1f}s to read aloud (max {MAX_SPEAK_SECONDS:.0f}s)")

    if topic and topic.get("category") in ("values", "safety"):
        text = " ".join([q["question"], *(options or []), q.get("explanation") or ""]).lower()
        for word in BANNED_IN_VALUES:
            if re.search(rf"\b{re.escape(word)}\b", text):
                report.error(where, f"contains '{word}', which values/safety content must avoid")
        if qtype in ("multipleChoice", "trueFalse") and not q.get("explanation"):
            report.warn(where, "values questions should have a kind 'explanation'")


def coverage(questions: list[dict], topics: dict[str, dict]) -> dict[str, dict[str, dict[str, int]]]:
    table = {tid: {band: {"scored": 0, "talk": 0} for band in t.get("ageBands", [])}
             for tid, t in topics.items()}
    for q in questions:
        cell = table.get(q.get("topic"), {}).get(q.get("ageBand"))
        if cell is not None:
            cell["talk" if q.get("type") == "talkAbout" else "scored"] += 1
    return table


def check_targets(table, report: Report) -> None:
    for tid, bands in table.items():
        for band, c in bands.items():
            where = f"coverage:{tid}:{band}"
            if tid == "manners":
                if c["scored"] < MANNERS_SCORED_PER_BAND:
                    report.error(where, f"{c['scored']}/{MANNERS_SCORED_PER_BAND} scored questions")
                if c["talk"] < MANNERS_TALK_PER_BAND:
                    report.error(where, f"{c['talk']}/{MANNERS_TALK_PER_BAND} Talk About prompts")
            elif c["scored"] + c["talk"] < TARGET_PER_BAND:
                report.error(where, f"{c['scored'] + c['talk']}/{TARGET_PER_BAND} questions")


def load_retired_ids(content: Path, report: Report) -> set[str]:
    path = content / "retired-ids.json"
    if not path.exists():
        return set()
    data = load_json(path, report)
    if not isinstance(data, list) or not all(isinstance(x, str) for x in data):
        report.error(path.name, "must be an array of question ids")
        return set()
    return set(data)


def validate(content: Path, strict: bool = False) -> tuple[Report, dict]:
    report = Report()
    catalogue = content / "topics.json"
    if not catalogue.exists():
        report.error(str(catalogue), "missing topic catalogue")
        return report, {}
    topics = validate_topics(load_json(catalogue, report), report)

    all_questions: list[dict] = []
    seen_ids: dict[str, str] = {}
    # Ids are permanent: players' Leitner boxes are stored by id (ADR-0016), so an id
    # must never move to another topic or be given to a new question after it's removed.
    retired = load_retired_ids(content, report)
    prefix_topic: dict[str, str] = {}
    topic_prefix: dict[str, str] = {}
    seen_text: dict[tuple[str, str], str] = {}
    files = sorted((content / "questions").glob("*.json"))
    if not files:
        report.error(str(content / "questions"), "no question files found")
    for path in files:
        data = load_json(path, report)
        if data is None:
            continue
        if not isinstance(data, list):
            report.error(path.name, "must be an array of questions")
            continue
        for i, q in enumerate(data):
            qid = q.get("id") if isinstance(q, dict) else None
            where = f"{path.name}:{qid or f'[{i}]'}"
            validate_question(q, where, topics, report)
            if not isinstance(q, dict):
                continue
            if qid in seen_ids:
                report.error(where, f"duplicate id (also in {seen_ids[qid]})")
            elif qid:
                seen_ids[qid] = path.name
            if isinstance(qid, str) and qid in retired:
                report.error(where, "id was retired and can't be reused; use the next free number")
            topic = q.get("topic")
            if isinstance(qid, str) and ID_PATTERN.match(qid) and isinstance(topic, str):
                prefix = qid[:3]
                owner = prefix_topic.setdefault(prefix, topic)
                expected = topic_prefix.setdefault(topic, prefix)
                if owner != topic:
                    report.error(where, f"id prefix '{prefix}' already belongs to topic {owner}")
                elif expected != prefix:
                    report.error(where, f"topic {topic} uses the id prefix '{expected}'")
            key = (q.get("ageBand", ""), normalise(str(q.get("question", ""))))
            if key in seen_text:
                report.warn(where, f"same question text as {seen_text[key]}")
            else:
                seen_text[key] = where
            all_questions.append(q)

    table = coverage(all_questions, topics)
    for tid, t in topics.items():
        if any(c["scored"] + c["talk"] for c in table[tid].values()) and t.get("requiresReview"):
            report.warn(f"topics.json:{tid}", "content requires parent/teacher review before release")
    if strict:
        check_targets(table, report)
    return report, table


def print_coverage(table) -> None:
    print(f"\nCoverage (scored + talkAbout per age band)\n{'topic':<18}" + "".join(f"{b:>14}" for b in AGE_BANDS))
    for tid, bands in table.items():
        cells = []
        for band in AGE_BANDS:
            c = bands.get(band)
            cells.append(("—" if c is None else f"{c['scored']}+{c['talk']}").rjust(14))
        print(f"{tid:<18}" + "".join(cells))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--content", type=Path, default=Path(__file__).resolve().parent.parent / "Content")
    parser.add_argument("--strict", action="store_true", help="also enforce launch content targets")
    parser.add_argument("--json", action="store_true", help="print a machine-readable report")
    args = parser.parse_args(argv)

    report, table = validate(args.content, strict=args.strict)
    if args.json:
        print(json.dumps({"errors": report.errors, "warnings": report.warnings, "coverage": table}, indent=2))
    else:
        print_coverage(table)
        for w in report.warnings:
            print(f"warning: {w}")
        for e in report.errors:
            print(f"error: {e}")
        total = sum(c["scored"] + c["talk"] for bands in table.values() for c in bands.values())
        print(f"\n{total} questions, {len(report.errors)} errors, {len(report.warnings)} warnings")
    return 1 if report.errors else 0


if __name__ == "__main__":
    sys.exit(main())
