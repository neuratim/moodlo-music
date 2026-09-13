/// Validates Moodlo's prompt library and turns paired renders into the public
/// catalogue consumed by the app.
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
const String _downloadBase =
    'https://raw.githubusercontent.com/neuratim/moodlo-music/main';
const String _licence =
    'CC0 1.0 Universal (public domain). Composed for NeuraTiM with generative AI. No attribution required.';
const List<int> _sampleRates = <int>[44100, 48000, 32000, 0];

Future<void> main() async {
  final root = Directory.current;
  final promptFile = File('${root.path}/100_mood_music_prompts.md');
  final intake = Directory('${root.path}/unprocessed');
  if (!promptFile.existsSync() || !intake.existsSync()) {
    stderr.writeln('Run from packages/moodlo/music.');
    exitCode = 64;
    return;
  }

  final prompts = _parsePrompts(await promptFile.readAsString());
  if (prompts.length != 100) {
    throw StateError('Expected 100 prompts, found ${prompts.length}.');
  }

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

  final existing = _readObject(File('${root.path}/catalogue.json'));
  final existingTracks = <String, Map<String, Object?>>{
    for (final value in (existing?['tracks'] as List<Object?>? ?? const []))
      if (value is Map<String, Object?> && value['id'] is String)
        value['id']! as String: value,
  };

  for (final entry in grouped.entries) {
    if (!prompts.containsKey(entry.key)) {
      throw FormatException('No prompt $entry.key exists.');
    }
    if (entry.value.length != 2) {
      throw FormatException(
        'Prompt ${entry.key} needs exactly two files, found ${entry.value.length}.',
      );
    }
    final suffixes = entry.value.map(_variantOf).toSet();
    if (!suffixes.containsAll(const <String>{'a', 'b'})) {
      throw FormatException(
        'Prompt ${entry.key} needs one A and one B render.',
      );
    }

    final target = Directory('${root.path}/tracks/${entry.key}')
      ..createSync(recursive: true);
    final versions = <Map<String, Object?>>[];
    for (final source
        in entry.value
          ..sort((a, b) => _variantOf(a).compareTo(_variantOf(b)))) {
      final variant = _variantOf(source);
      final bytes = await source.readAsBytes();
      final measured = _measureAudio(bytes);
      if (measured.seconds < 1) {
        throw FormatException(
          '${source.path} has no readable MPEG-1 Layer III frames.',
        );
      }
      final relative = 'tracks/${entry.key}/${entry.key}-$variant.mp3';
      final output = File(
        '${root.path}/${relative.replaceAll('/', Platform.pathSeparator)}',
      );
      if (!output.existsSync() ||
          sha256.convert(await output.readAsBytes()) != sha256.convert(bytes)) {
        await source.copy(output.path);
      }
      versions.add(<String, Object?>{
        'bytes': bytes.length,
        'id': variant,
        'name': _renderName(source),
        'path': relative,
        'seconds': measured.seconds.round(),
        'sha256': sha256.convert(bytes).toString(),
      });
    }
    existingTracks[entry.key] = <String, Object?>{
      ...prompts[entry.key]!,
      'versions': versions,
    };
  }

  final tracks = existingTracks.values.toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  for (final track in tracks) {
    final versions = track['versions'];
    if (versions is! List || versions.length != 2) {
      throw StateError(
        'Published track ${track['id']} does not have two versions.',
      );
    }
    final prompt = prompts[track['id']];
    if (prompt == null)
      throw StateError('Published track ${track['id']} has no prompt.');
    track.addAll(prompt);
  }

  final promptRows = prompts.values.toList()
    ..sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
  final genres =
      promptRows.map((row) => row['genre']! as String).toSet().toList()..sort();
  final catalogueFile = File('${root.path}/catalogue.json');
  final revision = _nextRevision(catalogueFile, tracks);
  await _writeJson(catalogueFile, <String, Object?>{
    'downloadBase': _downloadBase,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'genres': genres,
    'licence': _licence,
    'revision': revision,
    'schema': 1,
    'tracks': tracks,
  });
  await _writeJson(
    File('${root.path}/prompt_catalogue.json'),
    <String, Object?>{'prompts': promptRows, 'schema': 1},
  );
  stdout.writeln(
    'Published ${tracks.length} tracks and indexed ${prompts.length} prompts.',
  );
}

int _nextRevision(File file, List<Map<String, Object?>> tracks) {
  final previous = _readObject(file);
  final revision = previous?['revision'] is int
      ? previous!['revision']! as int
      : 0;
  if (previous != null &&
      jsonEncode(previous['tracks']) == jsonEncode(tracks)) {
    return revision;
  }
  return revision + 1;
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
  if (value is List<Object?>)
    return value.map(_sortJson).toList(growable: false);
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortJson(value[key]),
    };
  }
  return value;
}
