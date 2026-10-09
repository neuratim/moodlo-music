# Moodlo music

Moodlo's public, categorized music shelf. A composition has one render or several
numbered alternatives. Pressing Play in the app fetches the chosen render into one replaceable
temporary slot; Download is the explicit action that keeps it for offline use.

The shelf is divided into sections, listed in `sections.json`:

- **Motivation** (`m001`, `m002`, …) — bright, upbeat songs for a better mood,
  and the section the app opens on. Its tracks have no written brief, so their
  tempo and energy are measured from the audio (`analysis/motivation.json`).
- **Mood library** (`001`–`100`) — the hundred compositions briefed in
  `prompt_catalogue.json`, which retains their complete filter metadata.

The library ends at 100; every other section numbers on without limit under its
own prefix. `catalogue-v2.json` is the single playable catalogue the app reads.
`prompt_catalogue.json` indexes the 100 written assignments, including music
that is not available yet. See `PROCESSING.md` for the repeatable intake
procedure. Published files are CC0 1.0 Universal.

`m000` is the featured first Motivation track, “There’s Room in This Parade”.
Existing track IDs and audio remain unchanged. The app groups alternatives under
their composition title, labels them Version 1, Version 2, and so on, and shows
single tracks directly. Device-player artist metadata is always Moodlo.

After `dart pub get`, run `python -B -m unittest discover -s tool -p 'test_*.py' -v`
to verify catalogue generation in isolated fixtures. Dart, Python, and FFmpeg
must be available on PATH.
