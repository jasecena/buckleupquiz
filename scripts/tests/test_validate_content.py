"""Unit tests for scripts/validate_content.py. Run: python3 -m unittest discover -s scripts/tests"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import validate_content as vc  # noqa: E402

TOPICS = [
    {"id": "geography", "name": "Geography", "symbol": "globe", "color": "#2E86DE", "category": "knowledge",
     "isFree": True, "ageBands": ["6-8", "9-10", "11-12"], "requiresReview": False},
    {"id": "manners", "name": "Manners", "symbol": "heart", "color": "#E84393", "category": "values",
     "isFree": True, "ageBands": ["6-8", "9-10", "11-12"], "requiresReview": True},
    {"id": "space", "name": "Space", "symbol": "moon", "color": "#6C5CE7", "category": "knowledge",
     "isFree": True, "ageBands": ["6-8"], "requiresReview": False},
]


def question(**overrides):
    q = {"id": "geo-0001", "topic": "geography", "ageBand": "6-8", "type": "multipleChoice",
         "question": "What is the capital city of Tasmania?", "options": ["Launceston", "Hobart", "Darwin"],
         "answer": "Hobart",
         "acceptedAnswers": ["hobart"], "difficulty": 2, "minAge": None, "region": "AU"}
    q.update(overrides)
    return q


class ValidateContentTests(unittest.TestCase):
    def run_with(self, questions, topics=TOPICS, strict=False, retired=None):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "questions").mkdir()
            (root / "topics.json").write_text(json.dumps(topics))
            if retired is not None:
                (root / "retired-ids.json").write_text(json.dumps(retired))
            (root / "questions" / "q.json").write_text(json.dumps(questions))
            report, _ = vc.validate(root, strict=strict)
            return report

    def assertError(self, report, fragment):
        self.assertTrue(any(fragment in e for e in report.errors), f"{fragment!r} not in {report.errors}")

    def test_valid_question_passes(self):
        self.assertEqual(self.run_with([question()]).errors, [])

    def test_options_must_stand_on_their_own(self):
        vague = question(id="man-0001", topic="manners", question="A new kid is alone. What could you do?",
                         options=["Invite them to join you", "Wait for someone else to do it", "Walk away"],
                         answer="Invite them to join you", acceptedAnswers=[], explanation="Including helps.")
        self.assertError(self.run_with([vague]), "doesn't stand on its own")
        clear = dict(vague, options=["Invite them to join you", "Wait for someone else to invite them", "Walk away"])
        self.assertNotIn(True, ["stand on its own" in e for e in self.run_with([clear]).errors])

    def test_duplicate_ids(self):
        self.assertError(self.run_with([question(), question()]), "duplicate id")

    def test_retired_ids_cannot_come_back(self):
        self.assertError(self.run_with([question()], retired=["geo-0001"]), "retired")
        self.assertEqual(self.run_with([question()], retired=["geo-0099"]).errors, [])

    def test_each_topic_keeps_one_id_prefix(self):
        report = self.run_with([question(), question(id="xyz-0002", question="Which ocean is biggest?")])
        self.assertError(report, "uses the id prefix 'geo'")
        report = self.run_with([question(), question(id="geo-0002", topic="space", question="Which planet is red?")])
        self.assertError(report, "already belongs to topic geography")

    def test_open_questions_are_rejected(self):
        q = question(type="open", options=None)
        self.assertError(self.run_with([q]), "open quiz questions are not allowed")

    def test_multiple_choice_needs_exactly_three_options(self):
        self.assertError(self.run_with([question(options=["Hobart", "Darwin"])]), "exactly 3")
        self.assertError(self.run_with([question(options=["Hobart", "Darwin", "Perth", "Sydney"])]), "exactly 3")

    def test_scenario_type_points_to_multiple_choice(self):
        self.assertError(self.run_with([question(type="scenario")]), "merged into multipleChoice")

    def test_unknown_topic_and_band(self):
        self.assertError(self.run_with([question(topic="nope")]), "unknown topic")
        self.assertError(self.run_with([question(id="spc-0001", topic="space", ageBand="9-10")]), "no 9-10 band")

    def test_answer_must_be_an_option(self):
        q = question(options=["Indian", "Atlantic", "Arctic"], answer="Pacific")
        self.assertError(self.run_with([q]), "answer must be one of the options")

    def test_option_letters_not_allowed_in_accepted(self):
        q = question(type="multipleChoice", options=["Indian", "Pacific", "Atlantic"], answer="Pacific",
                     acceptedAnswers=["b"])
        self.assertError(self.run_with([q]), "option letters")

    def test_true_false_answer(self):
        q = question(type="trueFalse", question="Koalas are bears. True or false?", answer="Yes", acceptedAnswers=[])
        self.assertError(self.run_with([q]), "'True' or 'False'")

    def test_talk_about_has_no_answer(self):
        q = question(id="man-0001", topic="manners", type="talkAbout", question="What made you smile?",
                     answer="x", acceptedAnswers=[])
        self.assertError(self.run_with([q]), "talkAbout prompts have no answer")

    def test_speaking_length(self):
        long_q = " ".join(["word"] * 40) + "?"
        self.assertError(self.run_with([question(question=long_q)]), "to read aloud")

    def test_banned_words_in_values(self):
        q = question(id="man-0001", topic="manners", type="trueFalse", answer="True", acceptedAnswers=[],
                     question="Calling someone stupid is unkind. True or false?", explanation="Kind words matter.")
        self.assertError(self.run_with([q]), "'stupid'")

    def test_min_age_within_band(self):
        self.assertError(self.run_with([question(minAge=10)]), "minAge")

    def test_strict_enforces_targets(self):
        self.assertEqual(self.run_with([question()]).errors, [])
        self.assertError(self.run_with([question()], strict=True), "coverage:geography:6-8")

    def test_normalise(self):
        self.assertEqual(vc.normalise("The Pacific Ocean!"), "pacific ocean")
        self.assertEqual(vc.normalise("Don't"), "dont")

    def test_repository_content_is_valid(self):
        report, _ = vc.validate(Path(__file__).resolve().parents[2] / "Content")
        self.assertEqual(report.errors, [])


if __name__ == "__main__":
    unittest.main()
