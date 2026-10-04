"""Exercise the real catalogue generator in isolated intake directories."""

import hashlib
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[1]


class PrepareMusicTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="moodlo-catalogue-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("100_mood_music_prompts.md", "sections.json"):
            shutil.copyfile(REPOSITORY / name, self.root / name)
        audio = self.root / "fixture.mp3"
        subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                "anullsrc=r=44100:cl=stereo",
                "-t",
                "1.2",
                "-c:a",
                "libmp3lame",
                "-b:a",
                "128k",
                str(audio),
            ],
            check=True,
            capture_output=True,
        )
        self.audio = audio.read_bytes()
        for folder in ("unprocessed", "unprocessed/zoo"):
            intake = self.root / folder
            intake.mkdir(parents=True, exist_ok=True)
            for name in ("001-Render A.mp3", "001b-Render B.mp3"):
                (intake / name).write_bytes(self.audio)
        analysis = self.root / "analysis"
        analysis.mkdir()
        (analysis / "motivation.json").write_text(
            json.dumps(
                {
                    "renders": {
                        "m001-a": {"bpm": 120, "energy": 3},
                        "m001-b": {"bpm": 120, "energy": 3},
                    }
                }
            ),
            encoding="utf-8",
        )

    def generate(self):
        result = subprocess.run(
            [
                shutil.which("dart"),
                f"--packages={REPOSITORY / '.dart_tool/package_config.json'}",
                str(REPOSITORY / "tool/prepare_music.dart"),
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return json.loads((self.root / "catalogue-v2.json").read_text("utf-8"))

    def test_single_catalogue_preserves_sections_audio_and_repeat_revision(self):
        catalogue = self.generate()
        self.assertFalse((self.root / "catalogue.json").exists())
        self.assertEqual(catalogue["schema"], 2)
        self.assertEqual(catalogue["defaultSection"], "motivation")
        self.assertEqual([row["id"] for row in catalogue["tracks"]], ["m001", "001"])
        self.assertEqual(
            {row["id"] for row in catalogue["sections"]}, {"library", "motivation"}
        )
        for track in catalogue["tracks"]:
            self.assertEqual([row["id"] for row in track["versions"]], ["a", "b"])
            for version in track["versions"]:
                self.assertEqual((self.root / version["path"]).read_bytes(), self.audio)
                self.assertEqual(version["bytes"], len(self.audio))
                self.assertEqual(
                    version["sha256"], hashlib.sha256(self.audio).hexdigest()
                )
                self.assertGreaterEqual(version["seconds"], 1)
        prompts = json.loads((self.root / "prompt_catalogue.json").read_text("utf-8"))
        self.assertEqual(len(prompts["prompts"]), 100)
        # Existing published rows survive even after their intake originals leave.
        shutil.rmtree(self.root / "unprocessed")
        repeated = self.generate()
        self.assertEqual(repeated["tracks"], catalogue["tracks"])
        self.assertEqual(repeated["revision"], catalogue["revision"])
        self.assertFalse((self.root / "catalogue.json").exists())

    def test_obsolete_catalogue_is_not_read_or_overwritten(self):
        obsolete = self.root / "catalogue.json"
        content = json.dumps(
            {
                "revision": 9,
                "schema": 1,
                "tracks": [{"id": "002", "versions": [{"id": "a"}, {"id": "b"}]}],
            }
        ).encode()
        obsolete.write_bytes(content)
        catalogue = self.generate()
        self.assertEqual([row["id"] for row in catalogue["tracks"]], ["m001", "001"])
        self.assertEqual(obsolete.read_bytes(), content)


if __name__ == "__main__":
    unittest.main()
