# Moodlo music

Moodlo's public, categorized music shelf. Every composition has two alternative
renders. Pressing Play in the app fetches the chosen render into one replaceable
temporary slot; Download is the explicit action that keeps it for offline use.

The shelf is divided into sections, listed in `sections.json`:

- **Motivation** (`m001`, `m002`, …) — bright, upbeat songs for a better mood,
  and the section the app opens on. Its tracks have no written brief, so their
  tempo and energy are measured from the audio (`analysis/motivation.json`).
- **Mood library** (`001`–`100`) — the hundred compositions briefed in
  `100_mood_music_prompts.md`, which carries their complete filter metadata.

The library ends at 100; every other section numbers on without limit under its
own prefix. `catalogue-v2.json` is the single playable catalogue the app reads.
`prompt_catalogue.json` indexes the 100 written assignments, including music
that is not available yet. See `PROCESSING.md` for the repeatable intake
procedure. Published files are CC0 1.0 Universal.

After `dart pub get`, run `python -B -m unittest discover -s tool -p 'test_*.py' -v`
to verify catalogue generation in isolated fixtures. Dart, Python, and FFmpeg
must be available on PATH.
