# Processing new Moodlo music

Moodlo publishes each composition as a pair of alternative renders, filed in a
section from `sections.json`. Audio filenames are only render labels: a library
track's title and filters come from the prompt library, and a measured
section's from the audio.

## Sections

| Section      | Intake folder                         | Ids                                    | Facts come from             |
| ------------ | ------------------------------------- | -------------------------------------- | --------------------------- |
| `motivation` | `unprocessed/zoo/`                    | `m` + the file number (`m001`, `m101`) | `tool/analyze_audio.py`     |
| `library`    | `unprocessed/` (files directly in it) | the prompt number, `001`–`100`         | `100_mood_music_prompts.md` |

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
   `tracks/<id>/`, and regenerates `catalogue-v2.json` and the
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
  It is the single playable catalogue. `prompt_catalogue.json` keeps all 100 future assignments
  indexed without showing unavailable music in-app.
- A catalogue revision only increments when track metadata or audio changes.

The files in `tracks/` and the generated JSON are public CC0 assets. The intake
folders are staging only and must not be the source used by the app.

## Single catalogue cleanup: 2026-10-04

The user confirmed that Moodlo has not been released and removed the requirement
to preserve the old schema 1 music catalogue. `catalogue-v2.json` remains the
single playable catalogue; the metadata-only prompt index has a separate role.

| Requirement | Acceptance and verification                                                                                                                                            | Status   |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| CAT-01      | Remove `catalogue.json` and its generator output and fallback. Two isolated regression tests failed before the change and passed afterward.                            | VERIFIED |
| CAT-02      | Preserve sections, tracks, revision, prompt index, and all audio. Real regeneration kept 124 tracks, revision 3, and all 248 MP3 hashes and catalogue sizes unchanged. | VERIFIED |
| CAT-03      | Update active processing instructions and app references. The app already fetches schema 2; its URL is unchanged. Generator analysis and format checks passed.         | VERIFIED |

The integration fixtures cover fresh generation, both sections, complete A/B
pairs, hash/size verification, the 100-record prompt index, repeated runs after
intake removal, and ignoring an obsolete catalogue left in a directory.
Compatibility with schema 1 is REMOVED BY USER. Playback, network, localization,
and UI behavior are unchanged; no migrations or new dependencies are involved.
The earlier imports and ending corrections still await their required listening
review and are kept separate from this catalogue cleanup's local commits.

## Analysis report cleanup: 2026-10-04

At the user's request, removed the seven temporary ending-scan reports, fade
logs, and target list. The final ending scan passed for all 248 renders after
seven fade corrections; those results remain summarized in the processing record.
`analysis/motivation.json` is retained because the catalogue generator reads
its per-render measurements; it is a production input rather than a temporary
report. No music, catalogue, or measurement data was changed by this cleanup.

| Requirement | Verification                                                                               | Status   |
| ----------- | ------------------------------------------------------------------------------------------ | -------- |
| CLEAN-01    | All seven temporary reports are absent; their obsolete documentation links were removed.   | VERIFIED |
| CLEAN-02    | Required measurement input and both remaining catalogue files retain their SHA-256 hashes. | VERIFIED |

## Updated Motivation render: 2026-10-04

At the user's confirmation, refreshed the values for the user-supplied
`tracks/m001/m001-a.mp3`. The render is 195 seconds, 126 BPM, energy 4/4,
and 4,446,192 bytes. Its SHA-256 is
`0f5d2bac4b0a296ff6cd52445accdf206247eba550bc91f283af56c306650ee1`.
The composition length follows version A and is now 195 seconds.

- M001-01 VERIFIED: remeasured A using the existing audio-analysis tool and
  unchanged calibration against 97 library renders; refreshed its measurement
  input and regenerated its catalogue entry with the existing Dart tool.
- M001-02 VERIFIED: B and the other 123 working catalogue entries are unchanged;
  all 248 audio hashes are unchanged; a repeated generator run keeps the same
  records and revision. Unrelated intake and staged work are preserved.

## Import record: 2026-10-04

Historical records below mention the schema 1 catalogue produced at the time;
that compatibility output was subsequently removed at the user's request.

This records the initial import before the ending-correction pass below. That
pass supersedes the published-audio hashes and catalogue revisions reported here;
source originals remain unchanged.

Status: **IMPLEMENTED — VERIFICATION BLOCKED** until the listening review in
intake step 5 is confirmed. The following files have been prepared locally.

Source: `E:/Downloads/Music/mood/`. All 138 source originals are unchanged.
The 69 complete A/B pairs map to prompts `031`-`080` and `082`-`100`;
no render for `081` was supplied. Intake copies used three-digit numbers;
published filenames follow `tracks/NNN/NNN-a.mp3` and `tracks/NNN/NNN-b.mp3`.
The audio bytes and Unicode render names were preserved.

The import adds 726,532,725 audio bytes. The local shelf now contains 97 library
tracks and the existing 27 motivation tracks: 124 compositions, 248 renders.
Library prompts `012`, `014`, and `081` remain metadata-only. Existing published
track records and all 110 existing MP3s are unchanged.

`catalogue-v2.json` is revision 2, and `catalogue.json` is revision 3.
`prompt_catalogue.json` was regenerated and remains byte-for-byte unchanged,
with all 100 prompt records. The second importer run kept both revisions and
all track records unchanged; only the catalogue generation timestamps changed.

| Requirement                                              | Evidence                                                                                                                                              | Status   |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| R1: Account for every supplied render as a complete pair | 138 source files, 69 pairs, no duplicate variants or existing-id collisions                                                                           | VERIFIED |
| R2: Use prompt titles and filter metadata                | Every library record matches its complete bracketed tag line and prompt heading                                                                       | VERIFIED |
| R3: Preserve source files and existing published content | Source/output SHA-256 and byte counts match; existing records and audio match the baseline                                                            | VERIFIED |
| R4: Verify playback data and repeat processing           | All 138 files fully decode; measured duration agrees within rounding; schema, stable paths, sorted JSON keys, and unchanged repeat-run revisions pass | VERIFIED |
| R5: Review both versions by listening                    | Confirmation not yet supplied; decoding does not assess lyrics or musical quality                                                                     | BLOCKED  |
| R6: Verify and save the import locally                   | Asset checks, music tooling analysis, and all 17 workspace checks pass; local commit waits for the required listening review                          | BLOCKED  |

Verification performed from this music repository:

- `dart pub get`: passed.
- `dart run tool/prepare_music.dart`: passed twice, with 124 tracks and 100 prompts.
- `dart analyze`: passed, with no issues.
- FFmpeg fully decoded every source render with `-v error -xerror`, using the
  final decoded timestamp to check duration. Decoded lengths span 189.240 to
  254.904 seconds. FFprobe's bitrate-based estimates were not used as the
  duration acceptance check because they overestimate some variable-bitrate files.
- An independent Python check parsed all 100 prompt headings and tag lines,
  compared every library field, checked all source/staged/output hashes and
  byte counts, preserved existing records and audio, verified both catalogue
  schemas and paths, and checked repeat-run track and revision stability: passed.
- `npm run check moodlo` from `D:/code/neuratim`: passed, 17 checks and zero failures (app format, analysis, tests and release web build; admin and presentation-site checks).

The import is not committed or pushed. Listening review remains required by
step 5. Source originals remain in their supplied folder. Intake copies remain
in `unprocessed/` pending that review. All verification commands have completed;
no session-owned process remains running. Baseline and verification evidence
is retained at
`C:/Users/ticho/AppData/Local/Temp/moodlo-music-import-q_w06464/` for the review
and subsequent local commit.

### Prepared pairs

Durations below are the published, frame-measured seconds. Titles come from the
prompt library; alternative render names remain in each catalogue version.

| ID  | Prompt title               | A seconds | B seconds |
| --- | -------------------------- | --------- | --------- |
| 031 | Good Enough Today          | 195       | 195       |
| 032 | After-Class Skyline        | 210       | 210       |
| 033 | Borrowed Courage           | 205       | 204       |
| 034 | Starlight Group Chat       | 190       | 189       |
| 035 | Quiet Win                  | 215       | 215       |
| 036 | Side Quest Complete        | 199       | 199       |
| 037 | Paper Hearts Club          | 215       | 205       |
| 038 | Unsent Worries             | 205       | 205       |
| 039 | Bright Side Cypher         | 200       | 200       |
| 040 | Morning for Myself         | 190       | 190       |
| 041 | Balcony Reset              | 225       | 225       |
| 042 | Green Light Feeling        | 216       | 216       |
| 043 | One Stop Early             | 229       | 230       |
| 044 | Cheap Flowers              | 205       | 204       |
| 045 | City by Bicycle            | 200       | 199       |
| 046 | Start Again Softly         | 220       | 220       |
| 047 | Market Morning             | 194       | 195       |
| 048 | Clear Tab                  | 240       | 239       |
| 049 | Friends Around the Table   | 225       | 224       |
| 050 | Tomorrow Has Windows       | 240       | 239       |
| 051 | Kitchen Window Bossa       | 224       | 225       |
| 052 | Tiny Victories             | 214       | 215       |
| 053 | Detour by the River        | 230       | 230       |
| 054 | Desk to Daylight           | 210       | 210       |
| 055 | Dancing While Dinner Cooks | 205       | 205       |
| 056 | Ten Minutes of Sky         | 240       | 240       |
| 057 | Fresh Notebook             | 235       | 234       |
| 058 | Car Ride Confetti          | 190       | 206       |
| 059 | Lanterns in the Courtyard  | 220       | 220       |
| 060 | Unhurried Yes              | 230       | 229       |
| 061 | Sunday Open Door           | 225       | 227       |
| 062 | Vinyl in the Sun           | 235       | 235       |
| 063 | Second Bloom               | 220       | 220       |
| 064 | Creekside Footpath         | 205       | 205       |
| 065 | Electric Apricot           | 230       | 230       |
| 066 | Late Light Dance           | 245       | 245       |
| 067 | Familiar Road, New Shoes   | 225       | 224       |
| 068 | Garden Gate Tango          | 209       | 209       |
| 069 | Open Album                 | 235       | 235       |
| 070 | Still Learning the Tune    | 215       | 215       |
| 071 | Golden Hour Tram           | 229       | 230       |
| 072 | New Page Morning           | 224       | 224       |
| 073 | Warm Current               | 245       | 245       |
| 074 | Porch Swing Waltz          | 220       | 220       |
| 075 | Neighbors in Bloom         | 236       | 235       |
| 076 | Blue Sky Circuit           | 215       | 215       |
| 077 | Small Harbor, Wide Horizon | 225       | 225       |
| 078 | Rhythm Keeps Company       | 220       | 220       |
| 079 | Apricot Tea                | 240       | 240       |
| 080 | A Walk Worth Taking        | 225       | 225       |
| 082 | Slow Golden Groove         | 229       | 230       |
| 083 | Letters Full of Light      | 235       | 235       |
| 084 | Ribbon of Blue             | 225       | 224       |
| 085 | Another Little Adventure   | 214       | 214       |
| 086 | Satin Steps                | 230       | 230       |
| 087 | Courtyard Breeze           | 240       | 240       |
| 088 | Warm Glass Garden          | 250       | 250       |
| 089 | Together at Our Pace       | 235       | 235       |
| 090 | Morning Bellflowers        | 220       | 220       |
| 091 | A Hundred Small Suns       | 225       | 225       |
| 092 | Room for Every Rhythm      | 220       | 219       |
| 093 | Maple Street Bounce        | 205       | 205       |
| 094 | Ocean of Open Windows      | 240       | 240       |
| 095 | Bright Thread              | 204       | 204       |
| 096 | Four Seasons, One Garden   | 255       | 254       |
| 097 | Pocket Festival            | 195       | 195       |
| 098 | Try a Little Wonder        | 210       | 209       |
| 099 | Sunlit Patterns            | 235       | 235       |
| 100 | Room for Tomorrow          | 240       | 240       |

## Ending corrections: 2026-10-04

The requested ending check covered every playable render in `tracks/`: 248 MP3s
across both sections. The corrected checker found 241 passing endings and seven
renders needing a fade. After correction, **all 248 return `OK_FADE`**, with no
review flags or decoding errors. The script's verdict assesses amplitude decay;
the earlier import's separate listening review remains pending.

The first scan exposed three VBR-duration seek errors and incomplete-tail
assessments. `custom_scripts/check_audio_endings.py` now retries an empty or
incomplete EOF seek by decoding from the start and retaining the requested tail.
Its empty/partial-tail regression failed before the fix; all 17 script tests now
pass, including FFmpeg integration checks. `fade_audio_endings.py` uses that
same helper. Neither checker threshold nor fade verification was weakened.

| Render   | Final fade | Final check |
| -------- | ---------- | ----------- |
| `030-b`  | 8 seconds  | `OK_FADE`   |
| `045-a`  | 5 seconds  | `OK_FADE`   |
| `058-a`  | 5 seconds  | `OK_FADE`   |
| `m001-a` | 5 seconds  | `OK_FADE`   |
| `m008-a` | 5 seconds  | `OK_FADE`   |
| `m009-a` | 5 seconds  | `OK_FADE`   |
| `m023-b` | 5 seconds  | `OK_FADE`   |

The five-second attempt on `030-b` retained a review flag because its final
2.2 seconds were already silent. An eight-second candidate made from the original
unfaded backup passed and replaced that attempt, without compounding the fade.
All seven final renders preserve decoded sample counts, sample rates, channels,
descriptive tags, and artwork. The other 241 renders are byte-for-byte unchanged.

The user explicitly requested these replacements at existing published paths.
They are a maintenance exception to the ordinary new-id intake rule. The
original source files in `E:/Downloads/Music/mood/` remain untouched. Intake
copies of corrected renders were synchronized to avoid restoring unfaded audio
on the next importer run. Complete pairs were staged for the seven affected
compositions, including their unchanged alternatives.

Affected Motivation pairs were remeasured with `python tool/analyze_audio.py
motivation`; its energy calibration uses all 97 locally available library
A renders. `dart run tool/prepare_music.dart` regenerated both playable
catalogues: schema 2 is revision 3, schema 1 is revision 4. The prompt catalogue
remains byte-for-byte unchanged. All 248 version paths, byte counts, and SHA-256
values match the final files; all prompt metadata and composition titles remain
unchanged. The script fix is saved in local workspace commit `888eb52`; the
music import and corrections still await listening confirmation before their
local commit. Nothing was pushed.

| Requirement                                                 | Evidence                                                                                                              | Status   |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------- |
| E1: Check every playable render with the supplied checker   | Final report has 248 unique paths, all `OK_FADE`, zero errors                                                         | VERIFIED |
| E2: Fix every flagged ending with the supplied fade tool    | Seven replacements; six five-second fades and one eight-second fade from the original backup                          | VERIFIED |
| E3: Preserve audio identity and refresh catalogue integrity | Sample counts, formats, tags and artwork retained; 241 unchanged hashes; both catalogue schemas match all final files | VERIFIED |
| E4: Save the combined import and ending corrections locally | The separate import listening-review requirement remains unconfirmed                                                  | BLOCKED  |

The seven temporary reports in `analysis/` were removed at the user's request
after verification. Their results are summarized in this correction record.

The final scan used `--only-flagged --fail-on-flagged` and exited successfully.
Independent checks compared every catalogue hash and byte count, all original
and final sample counts and metadata for changed renders, and all 248 paths
against the pre-correction baseline. Seven unfaded backups and the correction
verification evidence are retained at
`C:/Users/ticho/AppData/Local/Temp/moodlo-music-endings-p8bgide6/`.

## New Motivation batch: 2026-10-04

Prepared the 20 numbered A/B pairs from `unprocessed/` as Motivation tracks
`m103`-`m122`. The user selected a uniform two-number offset: source 101 becomes
`m103`, through source 120 becoming `m122`. Existing `m101` (Open the Day) and
`m102` (Sunlit Strut) contain different songs and remain unchanged.

The local catalogue is revision 5: 144 compositions, 288 renders, comprising
47 Motivation and 97 library compositions. Titles follow A; alternative render
labels, including Japanese text and different A/B names, are preserved.
Both versions have independently measured tempo and energy. The existing
97-library-render calibration is unchanged; keys remain unpublished because
only 38 of 97 calibration keys match. No genre, language, or other unmeasurable
filter value was invented.

Five new renders needed the supplied five-second fade: `m106-a`, `m107-b`,
`m109-b`, `m110-b`, and `m115-a`. Corrected copies were remeasured before
catalogue generation. FFprobe confirms unchanged decoded sample counts;
the fade tool also verifies sample rate, channels, tags, and artwork.
All other 35 new renders preserve their original bytes. All 248 existing
published MP3 hashes and all 124 existing catalogue records are unchanged.

| Requirement | Acceptance and observed verification                                                                                                                                    | Status   |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| MOT-01      | Twenty complete numbered pairs use the user-approved IDs m103-m122, with no collision or half-published track.                                                          | VERIFIED |
| MOT-02      | All forty renders have measured BPM/energy, correct duration, byte count, SHA-256, stable paths, names, and Motivation moods.                                           | VERIFIED |
| MOT-03      | Final scan of the actual tracks folder passes for all 288 renders after five new fades; all 40 new renders fully decode.                                                | VERIFIED |
| MOT-04      | All 42 source originals, 248 existing audio hashes, 124 prior catalogue records, old measurements, and the 100-prompt index are preserved.                              | VERIFIED |
| MOT-05      | The real Dart generator passes twice with stable tracks/revision; the actual app parser accepts 144 tracks and measured filters; both generator integration tests pass. | VERIFIED |
| MOT-06      | `npm run check moodlo` passes all 17 gates, including 151 Flutter tests, 10 admin tests, and both release web builds.                                                   | VERIFIED |
| MOT-07      | The two unnumbered files need a confirmed A/B grouping and an unused ID.                                                                                                | BLOCKED  |
| MOT-08      | Intake step 5 listening review is unconfirmed, so intake archival and the local import commit remain pending.                                                           | BLOCKED  |

`I Choose the Road.mp3` and `There’s Room in This Parade.mp3` remain unchanged
and unpublished. Both pass the ending checker. Their pairing is not inferred
from filenames. All source originals remain in `unprocessed/` pending listening
review and disposition of the loose files. The batch was generated in an
isolated Motivation intake so root-folder inputs were never misclassified as
library prompts. Do not run the root importer against those unclassified
originals: it would reject their numbers/names. After review, move the originals
out of the active intake as required by step 5; reuse the corrected published
renders if reconstructing intake, so original audio cannot undo the fades.

Temporary ending reports and measurement dependencies are removed after
verification; the required production input `analysis/motivation.json` remains.
Nothing is pushed, and no session-owned process is left running.
