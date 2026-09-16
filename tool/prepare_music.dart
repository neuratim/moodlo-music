/// Validates Moodlo's music sections and turns paired renders into the public
/// catalogues consumed by the app.
///
/// `sections.json` lists every section. The library's facts come from
/// `100_mood_music_prompts.md`, which ends at 100. Every other section is
/// `measured`: its facts come from `tool/analyze_audio.py`, and its numbering
/// continues without limit under its own id prefix (`m001`, `m002`, …).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const List<int> _bitrates = <int>[
  0,
  32,
  40,
  48,
  56,
  64,
  80,
  96,
  112,
  128,
  160,
  192,
  224,
  256,
  320,
  0,
];
const String _catalogue = 'catalogue-v2.json';
const String _downloadBase =
    'https://raw.githubusercontent.com/neuratim/moodlo-music/main';

/// The schema-1 catalogue earlier app builds still fetch. It carries only the
/// library, whose ids and fields are the ones those builds can parse.
const String _legacyCatalogue = 'catalogue.json';
const String _librarySection = 'library';
const String _licence =
    'CC0 1.0 Universal (public domain). Composed for NeuraTiM with generative AI. No attribution required.';
const List<int> _sampleRates = <int>[44100, 48000, 32000, 0];

Future<void> main() async {
  final root = Directory.current;
  final promptFile = File('${root.path}/100_mood_music_prompts.md');
  final sectionsFile = File('${root.path}/sections.json');
  if (!promptFile.existsSync() || !sectionsFile.existsSync()) {
    stderr.writeln('Run from packages/moodlo/music.');
    exitCode = 64;
    return;
  }

  final prompts = _parsePrompts(await promptFile.readAsString());
  if (prompts.length != 100) {
    throw StateError('Expected 100 prompts, found ${prompts.length}.');
  }
  final sectionsJson = _readObject(sectionsFile)!;
  final sections = <Map<String, Object?>>[
    for (final section in sectionsJson['sections']! as List<Object?>)
      section! as Map<String, Object?>,
  ];
  final sectionOrder = <String, int>{
    for (final (index, section) in sections.indexed)
      section['id']! as String: index,
  };

  final existing =
      _readObject(File('${root.path}/$_catalogue')) ??
      _readObject(File('${root.path}/$_legacyCatalogue'));
  final tracks = <String, Map<String, Object?>>{
    for (final value in (existing?['tracks'] as List<Object?>? ?? const []))
      if (value is Map<String, Object?> && value['id'] is String)
        value['id']! as String: <String, Object?>{
          'section': _librarySection,
          ...value,
        },
  };
  final waiting = <String>[];

  for (final section in sections) {
    final sectionId = section['id']! as String;
    final prefix = section['prefix']! as String;
    final measured = section['metadata'] == 'measured';
    final intake = Directory('${root.path}/${section['intake']}');
    if (!intake.existsSync()) continue;
    final analysis = measured
        ? _readObject(File('${root.path}/analysis/$sectionId.json'))
        : null;
    final renders = analysis?['renders'] as Map<String, Object?>?;

    for (final entry in _pairs(intake).entries) {
      final trackId = '$prefix${entry.key}';
      if (!measured && !prompts.containsKey(entry.key)) {
        throw FormatException('No prompt ${entry.key} exists.');
      }
      final variants = entry.value.map(_variantOf).toSet();
      if (entry.value.length != 2 ||
          !variants.containsAll(const <String>{'a', 'b'})) {
        waiting.add('$trackId in ${section['intake']}: needs one A and one B');
        continue;
      }

      final target = Directory('${root.path}/tracks/$trackId')
        ..createSync(recursive: true);
      final versions = <Map<String, Object?>>[];
      for (final source
          in entry.value
            ..sort((a, b) => _variantOf(a).compareTo(_variantOf(b)))) {
        final variant = _variantOf(source);
        final bytes = await source.readAsBytes();
        final audio = _measureAudio(bytes);
        if (audio.seconds < 1) {
          throw FormatException(
            '${source.path} has no readable MPEG-1 Layer III frames.',
          );
        }
        final render = renders?['$trackId-$variant'];
        if (measured && render is! Map<String, Object?>) {
          throw StateError(
            '$trackId-$variant has no measurement. Run '
            '`python tool/analyze_audio.py $sectionId` first.',
          );
        }
        final relative = 'tracks/$trackId/$trackId-$variant.mp3';
        final output = File('${target.path}/$trackId-$variant.mp3');
        if (!output.existsSync() ||
            sha256.convert(await output.readAsBytes()) !=
                sha256.convert(bytes)) {
          await source.copy(output.path);
        }
        versions.add(<String, Object?>{
          if (render is Map<String, Object?>) ...<String, Object?>{
            'bpm': render['bpm'],
            'energy': render['energy'],
            if (render['key'] != null) 'key': render['key'],
          },
          'bytes': bytes.length,
          'id': variant,
          'name': _renderName(source),
          'path': relative,
          'seconds': audio.seconds.round(),
          'sha256': sha256.convert(bytes).toString(),
        });
      }
      tracks[trackId] = <String, Object?>{
        if (measured) ...<String, Object?>{
          'lengthSeconds': versions.first['seconds'],
          'moods': section['moods'],
          'title': versions.first['name'],
        } else
          ...prompts[entry.key]!,
        'id': trackId,
        'section': sectionId,
        'versions': versions,
      };
    }
  }

  for (final track in tracks.values) {
    final versions = track['versions'];
    if (versions is! List || versions.length != 2) {
      throw StateError(
        'Published track ${track['id']} does not have two versions.',
      );
    }
    if (!sectionOrder.containsKey(track['section'])) {
      throw StateError('Track ${track['id']} is in an unknown section.');
    }
    if (track['section'] == _librarySection) {
      final prompt = prompts[track['id']];
      if (prompt == null) {
        throw StateError('Published track ${track['id']} has no prompt.');
      }
      track.addAll(prompt);
    }
  }
  final ordered = tracks.values.toList()
    ..sort((a, b) {
      final bySection = sectionOrder[a['section']]!.compareTo(
        sectionOrder[b['section']]!,
      );
      return bySection != 0
          ? bySection
          : (a['id']! as String).compareTo(b['id']! as String);
    });

  final catalogueFile = File('${root.path}/$_catalogue');
  await _writeJson(catalogueFile, <String, Object?>{
    'defaultSection': sectionsJson['defaultSection'],
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'licence': _licence,
    'revision': _nextRevision(catalogueFile, ordered),
    'schema': 2,
    'sections': <Object?>[
      for (final section in sections)
        <String, Object?>{
          'id': section['id'],
          'localizations': section['localizations'],
        },
    ],
    'tracks': ordered,
  });

  final library = <Map<String, Object?>>[
    for (final track in ordered)
      if (track['section'] == _librarySection)
        <String, Object?>{
          for (final entry in track.entries)
            if (entry.key != 'section') entry.key: entry.value,
        },
  ];
  final promptRows = prompts.values.toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  final legacyFile = File('${root.path}/$_legacyCatalogue');
  await _writeJson(legacyFile, <String, Object?>{
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'genres':
        promptRows.map((row) => row['genre']! as String).toSet().toList()
          ..sort(),
    'licence': _licence,
    'revision': _nextRevision(legacyFile, library),
    'schema': 1,
    'tracks': library,
  });
  await _writeJson(
    File('${root.path}/prompt_catalogue.json'),
    <String, Object?>{'prompts': promptRows, 'schema': 1},
  );
  stdout.writeln(
    'Published ${ordered.length} tracks in ${sections.length} sections and '
    'indexed ${prompts.length} prompts.',
  );
  for (final line in waiting) {
    stdout.writeln('Left in intake: $line.');
  }
}

int _nextRevision(File file, List<Map<String, Object?>> tracks) {
  final previous = _readObject(file);
  final revision = previous?['revision'] is int
      ? previous!['revision']! as int
      : 0;
  if (previous != null &&
      jsonEncode(_sortJson(previous['tracks'])) ==
          jsonEncode(_sortJson(tracks))) {
    return revision;
  }
  return revision + 1;
}

/// The MP3s directly inside [intake], grouped by their three-digit number.
Map<String, List<File>> _pairs(Directory intake) {
  final grouped = <String, List<File>>{};
  for (final file in intake.listSync().whereType<File>().where(
    (file) => file.path.toLowerCase().endsWith('.mp3'),
  )) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(
      r'^(\d{3})(b)?-(.+)\.mp3$',
      caseSensitive: false,
    ).firstMatch(name);
    if (match == null) {
      throw FormatException('$name must be NNN-Title.mp3 or NNNb-Title.mp3.');
    }
    grouped.putIfAbsent(match.group(1)!, () => <File>[]).add(file);
  }
  return grouped;
}

Map<String, Object?> _parseTagLine(String line) {
  final result = <String, Object?>{};
  final body = line.substring(1, line.length - 1);
  String? currentKey;
  for (final raw in body.split(';')) {
    final part = raw.trim();
    final equals = part.indexOf('=');
    if (equals > 0) {
      currentKey = part.substring(0, equals).trim();
      final value = part.substring(equals + 1).trim();
      result[currentKey] = value;
    } else if (currentKey == 'mood') {
      result['mood'] = '${result['mood']};$part';
    } else {
      throw FormatException('Malformed tag segment "$part".');
    }
  }
  result['bpm'] = int.parse(result['bpm']! as String);
  result['energy'] = int.parse((result['energy']! as String).split('/').first);
  result['lengthSeconds'] = int.parse(
    (result.remove('length')! as String).replaceAll('s', ''),
  );
  result['moods'] = (result.remove('mood')! as String).split(';');
  return result;
}

Map<String, Map<String, Object?>> _parsePrompts(String source) {
  final prompts = <String, Map<String, Object?>>{};
  String? id;
  String? title;
  for (final line in const LineSplitter().convert(source)) {
    final heading = RegExp(r'^### (\d{3})\s+[—-]\s+(.+)$').firstMatch(line);
    if (heading != null) {
      id = heading.group(1);
      title = heading.group(2)!.trim();
      continue;
    }
    if (id == null || title == null || !line.startsWith('[id=$id;')) continue;
    final tags = _parseTagLine(line);
    if (tags['id'] != id) throw FormatException('Prompt id mismatch at $id.');
    prompts[id] = <String, Object?>{...tags, 'title': title};
    id = null;
    title = null;
  }
  return prompts;
}

Map<String, Object?>? _readObject(File file) {
  if (!file.existsSync()) return null;
  final decoded = jsonDecode(file.readAsStringSync());
  return decoded is Map<String, Object?> ? decoded : null;
}

String _renderName(File file) {
  final name = file.uri.pathSegments.last.replaceFirst(
    RegExp(r'\.mp3$', caseSensitive: false),
    '',
  );
  return name
      .replaceFirst(RegExp(r'^\d{3}b?-', caseSensitive: false), '')
      .trim();
}

String _variantOf(File file) =>
    RegExp(
          r'^\d{3}(b)?-',
          caseSensitive: false,
        ).firstMatch(file.uri.pathSegments.last)!.group(1) ==
        null
    ? 'a'
    : 'b';

({Set<int> rates, double seconds}) _measureAudio(List<int> bytes) {
  var position = 0;
  if (bytes.length > 10 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33) {
    final size =
        (bytes[6] & 0x7F) << 21 |
        (bytes[7] & 0x7F) << 14 |
        (bytes[8] & 0x7F) << 7 |
        (bytes[9] & 0x7F);
    position = 10 + size;
  }
  final rates = <int>{};
  var total = 0.0;
  while (position + 4 <= bytes.length) {
    if (bytes[position] != 0xFF || (bytes[position + 1] & 0xE0) != 0xE0) {
      position++;
      continue;
    }
    final versionBits = (bytes[position + 1] >> 3) & 0x03;
    final layerBits = (bytes[position + 1] >> 1) & 0x03;
    final bitrate = _bitrates[(bytes[position + 2] >> 4) & 0x0F];
    final sampleRate = _sampleRates[(bytes[position + 2] >> 2) & 0x03];
    final padding = (bytes[position + 2] >> 1) & 0x01;
    if (versionBits != 3 || layerBits != 1 || bitrate == 0 || sampleRate == 0) {
      position++;
      continue;
    }
    final length = (144 * bitrate * 1000) ~/ sampleRate + padding;
    if (length <= 4 || position + length > bytes.length) break;
    rates.add(sampleRate);
    total += 1152 / sampleRate;
    position += length;
  }
  return (rates: rates, seconds: total);
}

Future<void> _writeJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(_sortJson(value))}\n',
  );
}

Object? _sortJson(Object? value) {
  if (value is List<Object?>) {
    return value.map(_sortJson).toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortJson(value[key]),
    };
  }
  return value;
}
