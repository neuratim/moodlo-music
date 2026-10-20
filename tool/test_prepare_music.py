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
        shutil.copyfile(REPOSITORY / "prompt_catalogue.json", self.root / "prompt_catalogue.json")
        # The real sections, without the featured order of the real shelf.
        sections = json.loads((REPOSITORY / "sections.json").read_text("utf-8"))
        for section in sections["sections"]:
            section.pop("featured", None)
        self.write_sections(sections)
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

    def write_sections(self, sections):
        (self.root / "sections.json").write_text(json.dumps(sections), encoding="utf-8")

    def feature(self, *track_ids):
        sections = json.loads((self.root / "sections.json").read_text("utf-8"))
        sections["sections"][0]["featured"] = list(track_ids)
        self.write_sections(sections)

    def generate_failing(self):
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
        self.assertNotEqual(result.returncode, 0, result.stdout)
        return result.stdout + result.stderr

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

    def test_featured_tracks_lead_their_section_in_the_listed_order(self):
        intake = self.root / "unprocessed/zoo"
        for name in ("000-First.mp3", "026-Second.mp3"):
            (intake / name).write_bytes(self.audio)
        analysis = self.root / "analysis/motivation.json"
        measured = json.loads(analysis.read_text("utf-8"))
        for render in ("m000-a", "m026-a"):
            measured["renders"][render] = {"bpm": 120, "energy": 3}
        analysis.write_text(json.dumps(measured), encoding="utf-8")
        plain = self.generate()
        self.assertEqual(
            [row["id"] for row in plain["tracks"]], ["m000", "m001", "m026", "001"]
        )
        self.feature("m000", "m026")
        featured = self.generate()
        self.assertEqual(
            [row["id"] for row in featured["tracks"]], ["m000", "m026", "m001", "001"]
        )
        self.assertEqual(featured["sections"][0]["featured"], ["m000", "m026"])
        self.assertNotIn("featured", featured["sections"][1])
        self.assertEqual(featured["revision"], plain["revision"] + 1)
        self.assertEqual(self.generate()["revision"], featured["revision"])

    def test_a_featured_id_that_is_not_in_the_section_or_repeats_is_refused(self):
        self.feature("m404")
        self.assertIn("m404, which is not one of its tracks", self.generate_failing())
        self.feature("001")
        self.assertIn("001, which is not one of its tracks", self.generate_failing())
        self.feature("m001", "m001")
        self.assertIn("m001 is featured twice", self.generate_failing())

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

    def test_standalone_render_is_published_first_and_survives_repeat_generation(self):
        intake = self.root / "unprocessed/zoo"
        (intake / "000-There’s Room in This Parade.mp3").write_bytes(self.audio)
        analysis = self.root / "analysis/motivation.json"
        measurements = json.loads(analysis.read_text("utf-8"))
        measurements["renders"]["m000-a"] = {"bpm": 118, "energy": 4}
        analysis.write_text(json.dumps(measurements), encoding="utf-8")
        catalogue = self.generate()
        first = catalogue["tracks"][0]
        self.assertEqual(first["id"], "m000")
        self.assertEqual(first["title"], "There’s Room in This Parade")
        self.assertEqual(len(first["versions"]), 1)
        self.assertEqual(first["versions"][0]["bpm"], 118)
        self.assertEqual(
            first["versions"][0]["sha256"], hashlib.sha256(self.audio).hexdigest()
        )
        shutil.rmtree(intake)
        repeated = self.generate()
        self.assertEqual(repeated["tracks"], catalogue["tracks"])
        self.assertEqual(repeated["revision"], catalogue["revision"])

    def test_third_render_has_a_stable_path_and_numbered_identity(self):
        intake = self.root / "unprocessed"
        (intake / "001c-Render C.mp3").write_bytes(self.audio)
        library = self.generate()["tracks"][1]
        self.assertEqual(
            [version["id"] for version in library["versions"]], ["a", "b", "c"]
        )
        self.assertEqual(library["versions"][2]["path"], "tracks/001/001-c.mp3")

    def test_partial_intake_cannot_remove_a_published_version(self):
        catalogue = self.generate()
        (self.root / "unprocessed/001b-Render B.mp3").unlink()
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
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must include every existing render", result.stderr)
        self.assertEqual(
            json.loads((self.root / "catalogue-v2.json").read_text("utf-8")), catalogue
        )


    def webp(self, name, size):
        path = self.root / "artwork" / name
        path.parent.mkdir(exist_ok=True)
        subprocess.run(
            [
                "ffmpeg",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                f"color=c=orange:s={size}",
                "-frames:v",
                "1",
                "-y",
                str(path),
            ],
            check=True,
            capture_output=True,
        )
        return path.read_bytes()

    def run_tool(self):
        return subprocess.run(
            [
                shutil.which("dart"),
                f"--packages={REPOSITORY / '.dart_tool/package_config.json'}",
                str(REPOSITORY / "tool/prepare_music.dart"),
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
        )

    def test_a_cover_is_published_with_its_size_and_hash_and_bumps_the_revision(self):
        before = self.generate()
        self.assertNotIn("artwork", before["tracks"][1])
        cover = self.webp("001.webp", "320x320")
        catalogue = self.generate()
        library = catalogue["tracks"][1]
        self.assertEqual(
            library["artwork"],
            {
                "bytes": len(cover),
                "path": "artwork/001.webp",
                "sha256": hashlib.sha256(cover).hexdigest(),
            },
        )
        self.assertNotIn("artwork", catalogue["tracks"][0], "No cover, no entry")
        self.assertEqual(catalogue["revision"], before["revision"] + 1)
        self.assertEqual(self.generate()["revision"], catalogue["revision"])
        # Removing the cover takes it out again.
        (self.root / "artwork/001.webp").unlink()
        self.assertNotIn("artwork", self.generate()["tracks"][1])

    def test_a_cover_that_is_not_square_or_not_a_track_is_refused(self):
        catalogue = self.generate()
        self.webp("001.webp", "320x200")
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be square", result.stderr)
        (self.root / "artwork/001.webp").unlink()
        self.webp("077.webp", "320x320")
        result = self.run_tool()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not the cover of a published track", result.stderr)
        self.assertEqual(
            json.loads((self.root / "catalogue-v2.json").read_text("utf-8")), catalogue
        )


if __name__ == "__main__":
    unittest.main()
