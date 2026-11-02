import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch

from engine.python.basketball_engine.adapters import export
from engine.python.basketball_engine.adapters.export import merge_duplicate_auto_candidates


def candidate(time, start, end, **extra):
    return {
        "source_path": "game.mp4",
        "event_time_ms": time,
        "review_start_ms": start,
        "review_end_ms": end,
        "manual": False,
        **extra,
    }


class DuplicateGoalExportTest(unittest.TestCase):
    def test_separate_export_writes_one_file_for_duplicate_auto_events(self):
        clips = [
            candidate(11370, 6370, 13370, review_status="pending"),
            candidate(13500, 8500, 15500, review_status="goal"),
        ]

        def write_clip(_command, path, codecs, **_kwargs):
            path.write_bytes(b"test clip")
            return codecs[0]

        with tempfile.TemporaryDirectory() as directory:
            with patch.object(export, "video_codecs", return_value=["mpeg4"]), \
                 patch.object(export, "run_encoded_ffmpeg", side_effect=write_clip):
                result = export.export_goal_clips(clips, Path(directory), "separate")

        self.assertEqual(len(result["clip_files"]), 1)
        self.assertIn("13.50s", result["clip_files"][0])
        self.assertEqual(result["merged_overlap_count"], 1)

    def test_overlapping_auto_candidates_for_one_goal_become_one_clip(self):
        clips = [
            candidate(11370, 6370, 13370, review_status="pending"),
            candidate(13500, 8500, 15500, review_status="goal"),
        ]

        merged = merge_duplicate_auto_candidates(clips)

        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["review_start_ms"], 6370)
        self.assertEqual(merged[0]["review_end_ms"], 15500)
        self.assertEqual(merged[0]["event_time_ms"], 13500)
        self.assertEqual(merged[0]["review_status"], "goal")

    def test_distinct_goals_and_manual_clips_stay_separate(self):
        clips = [
            candidate(10000, 6000, 12000),
            candidate(14000, 10000, 16000),
            candidate(11000, 7000, 13000, manual=True),
        ]

        self.assertEqual(len(merge_duplicate_auto_candidates(clips)), 3)

    def test_different_video_or_player_stays_separate(self):
        clips = [
            candidate(10000, 6000, 12000, player_name="A"),
            candidate(11000, 7000, 13000, player_name="B"),
            candidate(11500, 7500, 13500, source_path="other.mp4", player_name="A"),
        ]

        self.assertEqual(len(merge_duplicate_auto_candidates(clips)), 3)

    def test_nearby_events_at_different_hoops_stay_separate(self):
        clips = [
            candidate(10000, 6000, 12000,
                      rim={"x": 200, "y": 200, "width": 30}),
            candidate(11000, 7000, 13000,
                      rim={"x": 800, "y": 200, "width": 30}),
        ]

        self.assertEqual(len(merge_duplicate_auto_candidates(clips)), 2)

    def test_invalid_range_is_not_hidden_by_duplicate_merge(self):
        clips = [candidate(10000, 6000, 12000), candidate(11000, 7000, 7000)]

        with self.assertRaisesRegex(ValueError, "INVALID_CLIP_RANGE"):
            merge_duplicate_auto_candidates(clips)


if __name__ == "__main__":
    unittest.main()
