# Processing new Moodlo music

Moodlo publishes each composition as a pair of alternative renders. The prompt
library is authoritative for the composition title and all filter flags; audio
filenames are only render labels.

## Intake contract

1. Put exactly two MP3 files for a prompt in `unprocessed/`:
   `NNN-Render name.mp3` and `NNNb-Render name.mp3`. `NNN` must exist in
   `100_mood_music_prompts.md`. The first file becomes version A, the `b` file
   version B. Different render names are allowed.
2. From this repository run:

   ```sh
   dart pub get
   dart run tool/prepare_music.dart
   ```

3. The tool validates all 100 prompt records, requires a complete A/B pair,
   measures MP3 frame duration, calculates SHA-256 and byte counts, copies the
   audio to stable paths under `tracks/NNN/`, and regenerates `catalogue.json`
   plus the complete metadata-only `prompt_catalogue.json`.
4. Review both versions by listening, inspect the generated diff, then move the
   intake originals out of `unprocessed/`. Do not rename published paths or
   replace audio under an existing track/version id; publish a new id instead.
5. Commit and push this repository. The app accepts only HTTPS files below the
   fixed `neuratim/moodlo-music` raw-GitHub path and verifies size and SHA-256.

## Metadata rules

- All filters come from the bracketed tag line in the prompt library: age,
  genre, style, moods, energy, vocals, language, use, BPM, meter, intended
  length, key, and content rating.
- Suggested age is a creative/filtering hint, never an access restriction.
  With no preferences or filters, Moodlo shows every published composition.
- Every catalogue track always has exactly two versions. Incomplete pairs are
  rejected rather than guessed.
- `catalogue.json` contains only playable pairs. `prompt_catalogue.json` keeps
  all 100 future assignments indexed without showing unavailable music in-app.
- A catalogue revision only increments when track metadata or audio changes.

The files in `tracks/` and the generated JSON are public CC0 assets. The intake
folder is staging only and must not be the source used by the app.
