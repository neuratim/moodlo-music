# Processing new Moodlo music

Moodlo publishes each composition as a pair of alternative renders, filed in a
section from `sections.json`. Audio filenames are only render labels: a library
track's title and filters come from the prompt library, and a measured
section's from the audio.

## Sections

| Section | Intake folder | Ids | Facts come from |
| --- | --- | --- | --- |
| `motivation` | `unprocessed/zoo/` | `m` + the file number (`m001`, `m101`) | `tool/analyze_audio.py` |
| `library` | `unprocessed/` (files directly in it) | the prompt number, `001`–`100` | `100_mood_music_prompts.md` |

A new section is one entry in `sections.json`: an id, an intake folder, an id
prefix, its moods, `"metadata": "measured"` and its name in all 18 app
languages. `defaultSection` is the one the app opens on.

## Intake contract

1. Put exactly two MP3 files for a composition in its section's intake folder:
   `NNN-Render name.mp3` and `NNNb-Render name.mp3`. For the library, `NNN`
   must exist in `100_mood_music_prompts.md`. The first file becomes version A,
   the `b` file version B. Different render names are allowed.
2. For a measured section, measure the renders first (numpy and soundfile, no
   other dependency; libsndfile ≥ 1.1 decodes MP3):

   ```sh
   python -m pip install -r tool/requirements.txt
   python tool/analyze_audio.py motivation
   ```

   It writes `analysis/<section>.json`: length, tempo, energy and a key estimate
   per render. Energy is fitted to the library's declared energy, and the file
   records how well the fit and the tempo agree with the library. A key is
   published only when the estimate matches the library's declared keys on at
   least 60 % of its tracks; otherwise it stays in the file as `keyEstimate`.
3. From this repository run:

   ```sh
   dart pub get
   dart run tool/prepare_music.dart
   ```

4. The tool validates all 100 prompt records, publishes every complete A/B pair
   and lists any incomplete one it left in intake, measures MP3 frame duration,
   calculates SHA-256 and byte counts, copies the audio to stable paths under
   `tracks/<id>/`, and regenerates `catalogue-v2.json`, `catalogue.json` and the
   metadata-only `prompt_catalogue.json`.
5. Review both versions by listening, inspect the generated diff, then move the
   intake originals out of their folder. Do not rename published paths or
   replace audio under an existing track/version id; publish a new id instead.
6. Commit and push this repository. The app accepts only HTTPS files below the
   fixed `neuratim/moodlo-music` raw-GitHub path and verifies size and SHA-256.

## Metadata rules

- A library track's filters come from the bracketed tag line in the prompt
  library: age, genre, style, moods, energy, vocals, language, use, BPM, meter,
  intended length, key, and content rating.
- A measured track carries its title (the A render's name), its section's
  moods, its length, and per render the measured tempo and energy — plus the key
  when it is reliable. Anything that cannot be measured is left out rather than
  guessed, and the app's filters simply do not offer it for that track.
- Suggested age is a creative/filtering hint, never an access restriction.
- Every catalogue track always has exactly two versions. Incomplete pairs stay
  in intake rather than being published half-made.
- `catalogue-v2.json` (schema 2) contains every playable pair in every section.
  `catalogue.json` (schema 1) contains the library alone, for app builds that
  predate sections. `prompt_catalogue.json` keeps all 100 future assignments
  indexed without showing unavailable music in-app.
- A catalogue revision only increments when track metadata or audio changes.

The files in `tracks/` and the generated JSON are public CC0 assets. The intake
folders are staging only and must not be the source used by the app.
