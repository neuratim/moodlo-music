/// Validates Moodlo's music sections and turns renders into the public
/// catalogue consumed by the app.
///
/// `sections.json` lists every section. The library's facts come from
/// `prompt_catalogue.json`, which ends at 100. Every other section is
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

const String _librarySection = 'library';
const String _licence =
    'CC0 1.0 Universal (public domain). Composed for NeuraTiM with generative AI. No attribution required.';
const List<int> _sampleRates = <int>[44100, 48000, 32000, 0];

Future<void> main() async {
  final root = Directory.current;
  final promptFile = File('${root.path}/prompt_catalogue.json');
  final sectionsFile = File('${root.path}/sections.json');
  if (!promptFile.existsSync() || !sectionsFile.existsSync()) {
    stderr.writeln('Run from packages/moodlo/music.');
    exitCode = 64;
    return;
  }

  final promptIndex = _readObject(promptFile)!;
  final prompts = <String, Map<String, Object?>>{
    for (final value in promptIndex['prompts']! as List<Object?>)
      if (value is Map<String, Object?> && value['id'] is String)
        value['id']! as String: value,
  };
  if (promptIndex['schema'] != 1 ||
      (promptIndex['prompts']! as List<Object?>).length != 100 ||
      prompts.length != 100 ||
      !List.generate(
        100,
        (index) => (index + 1).toString().padLeft(3, '0'),
      ).every(prompts.containsKey)) {
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

  final existing = _readObject(File('${root.path}/$_catalogue'));
  final tracks = <String, Map<String, Object?>>{
    for (final value in (existing?['tracks'] as List<Object?>? ?? const []))
      if (value is Map<String, Object?> && value['id'] is String)
        value['id']! as String: <String, Object?>{
          'section': _librarySection,
          ...value,
        },
  };
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
      final variants = entry.value.map(_variantOf).toList()..sort();
      final prior =
          tracks[trackId]?['versions'] as List<Object?>? ?? const <Object?>[];
      if (prior.any(
        (version) =>
            !variants.contains((version! as Map<String, Object?>)['id']),
      )) {
        throw FormatException(
          '$trackId intake must include every existing render.',
        );
      }
      if (variants.indexed.any(
        (entry) => entry.$2 != String.fromCharCode(97 + entry.$1),
      )) {
        throw FormatException(
          '$trackId needs unique consecutive renders from A.',
        );
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
    if (versions is! List || versions.isEmpty || versions.length > 26) {
      throw StateError(
        'Published track ${track['id']} needs one to 26 versions.',
      );
    }
    final variants = <String>[
      for (final version in versions) (version as Map)['id'] as String,
    ]..sort();
    if (variants.indexed.any(
      (entry) => entry.$2 != String.fromCharCode(97 + entry.$1),
    )) {
      throw StateError('Published track ${track['id']} has invalid versions.');
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

  final promptRows = prompts.values.toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  await _writeJson(
    File('${root.path}/prompt_catalogue.json'),
    <String, Object?>{'prompts': promptRows, 'schema': 1},
  );
  stdout.writeln(
    'Published ${ordered.length} tracks in ${sections.length} sections and '
    'indexed ${prompts.length} prompts.',
  );
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
      r'^(\d{3})([b-z])?-(.+)\.mp3$',
      caseSensitive: false,
    ).firstMatch(name);
    if (match == null) {
      throw FormatException(
        '$name must be NNN-Title.mp3 or NNN[b-z]-Title.mp3.',
      );
    }
    grouped.putIfAbsent(match.group(1)!, () => <File>[]).add(file);
  }
  return grouped;
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
      .replaceFirst(RegExp(r'^\d{3}[b-z]?-', caseSensitive: false), '')
      .trim();
}

String _variantOf(File file) =>
    RegExp(
      r'^\d{3}([b-z])?-',
      caseSensitive: false,
    ).firstMatch(file.uri.pathSegments.last)!.group(1)?.toLowerCase() ??
    'a';

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
