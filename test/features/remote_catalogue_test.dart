/// Unit tests for the remote catalogue layer: parsing a downloaded payload and
/// folding it over the bundled catalogue.
///
/// These are pure functions over plain data, so no widgets and no mocks are
/// needed — just hand-built [Fact] fixtures.
library;

import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/domain/remote_catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper to build a test fact with the given id. All fields are filled with
/// dummy data but are consistent for easy inspection.
Fact _buildFact(String id, {String question = 'question'}) {
  return Fact(
    id: id,
    category: FactCategory.body,
    question: LocalizedText(es: question, en: question),
    answer: LocalizedText(es: 'answer $id', en: 'answer $id'),
    detail: LocalizedText(es: 'detail $id', en: 'detail $id'),
    source: 'source $id',
    sourceUrl: '',
  );
}

/// A well-formed entry for the "facts" array, as raw JSON text.
String _entryJson({
  required String id,
  String category = 'cuerpo',
  bool withAnswer = true,
}) {
  final String answerField = withAnswer ? '"answer":{"es":"a","en":"a"},' : '';
  return '''
    {
      "id": "$id",
      "category": "$category",
      "question": {"es": "q", "en": "q"},
      $answerField
      "detail": {"es": "d", "en": "d"},
      "source": "s",
      "sourceUrl": ""
    }
  ''';
}

void main() {
  group('parseRemoteCatalogue', () {
    test('parses version, facts and removed from a well-formed payload', () {
      final RemoteCatalogue catalogue = parseRemoteCatalogue('''
      {
        "version": 3,
        "facts": [${_entryJson(id: 'new-1')}, ${_entryJson(id: 'new-2', category: 'ciencia')}],
        "removed": ["old-1", "old-2"]
      }
      ''');

      expect(catalogue.version, 3);
      expect(catalogue.facts.map((Fact fact) => fact.id), <String>[
        'new-1',
        'new-2',
      ]);
      expect(catalogue.removed, <String>['old-1', 'old-2']);
      expect(catalogue.skipped, 0);
    });

    test('a malformed entry is skipped and counted, valid entries survive', () {
      // The entry for "bad-category" carries a category that does not exist
      // and the entry for "bad-missing" has no "answer" field: both must be
      // dropped without taking the well-formed entries with them.
      final RemoteCatalogue catalogue = parseRemoteCatalogue('''
      {
        "version": 1,
        "facts": [
          ${_entryJson(id: 'good-1')},
          ${_entryJson(id: 'bad-category', category: 'no-existe')},
          ${_entryJson(id: 'bad-missing', withAnswer: false)},
          ${_entryJson(id: 'good-2')}
        ],
        "removed": []
      }
      ''');

      expect(catalogue.facts.map((Fact fact) => fact.id), <String>[
        'good-1',
        'good-2',
      ]);
      expect(catalogue.skipped, 2);
    });

    test('a payload that is not a JSON object throws FormatException', () {
      expect(
        () => parseRemoteCatalogue('"just a string"'),
        throwsFormatException,
      );
    });

    test('a payload with no integer version throws FormatException', () {
      expect(
        () => parseRemoteCatalogue('{"facts": [], "removed": []}'),
        throwsFormatException,
      );
      expect(
        () => parseRemoteCatalogue(
          '{"version": "3", "facts": [], "removed": []}',
        ),
        throwsFormatException,
      );
    });

    test('missing facts and removed keys default to empty', () {
      final RemoteCatalogue catalogue = parseRemoteCatalogue('{"version": 5}');

      expect(catalogue.facts, isEmpty);
      expect(catalogue.removed, isEmpty);
      expect(catalogue.skipped, 0);
      expect(catalogue.isEmpty, isTrue);
    });
  });

  group('mergeCatalogues', () {
    test(
      'a remote fact with an existing id replaces the bundled one in place',
      () {
        final List<Fact> bundled = <Fact>[
          _buildFact('a'),
          _buildFact('b'),
          _buildFact('c'),
        ];
        final RemoteCatalogue overlay = RemoteCatalogue(
          version: 1,
          facts: <Fact>[_buildFact('b', question: 'corrected')],
          removed: const <String>[],
        );

        final List<Fact> merged = mergeCatalogues(bundled, overlay);

        expect(merged.map((Fact fact) => fact.id), <String>[
          'a',
          'b',
          'c',
        ], reason: 'position must not move');
        expect(merged[1].question.es, 'corrected');
      },
    );

    test('ids in removed disappear', () {
      final List<Fact> bundled = <Fact>[
        _buildFact('a'),
        _buildFact('b'),
        _buildFact('c'),
      ];
      const RemoteCatalogue overlay = RemoteCatalogue(
        version: 1,
        facts: <Fact>[],
        removed: <String>['b'],
      );

      final List<Fact> merged = mergeCatalogues(bundled, overlay);

      expect(merged.map((Fact fact) => fact.id), <String>['a', 'c']);
    });

    test('new ids are appended at the end, in remote order', () {
      final List<Fact> bundled = <Fact>[_buildFact('a'), _buildFact('b')];
      final RemoteCatalogue overlay = RemoteCatalogue(
        version: 1,
        facts: <Fact>[_buildFact('z'), _buildFact('y')],
        removed: const <String>[],
      );

      final List<Fact> merged = mergeCatalogues(bundled, overlay);

      expect(merged.map((Fact fact) => fact.id), <String>['a', 'b', 'z', 'y']);
    });

    test('a null overlay returns the bundled list unchanged', () {
      final List<Fact> bundled = <Fact>[_buildFact('a'), _buildFact('b')];

      expect(mergeCatalogues(bundled, null), same(bundled));
    });

    test(
      'an overlay with no facts and no removals returns the bundled list unchanged',
      () {
        final List<Fact> bundled = <Fact>[_buildFact('a'), _buildFact('b')];
        const RemoteCatalogue overlay = RemoteCatalogue(
          version: 1,
          facts: <Fact>[],
          removed: <String>[],
        );

        expect(mergeCatalogues(bundled, overlay), same(bundled));
      },
    );

    test(
      'an overlay that removes every bundled id returns the bundled list, not an empty one',
      () {
        final List<Fact> bundled = <Fact>[
          _buildFact('a'),
          _buildFact('b'),
          _buildFact('c'),
        ];
        const RemoteCatalogue overlay = RemoteCatalogue(
          version: 1,
          facts: <Fact>[],
          removed: <String>['a', 'b', 'c'],
        );

        final List<Fact> merged = mergeCatalogues(bundled, overlay);

        expect(merged, same(bundled));
        expect(merged, isNotEmpty);
      },
    );

    test('the merged list never contains duplicate ids, even when the overlay '
        'repeats an id that is also in removed', () {
      final List<Fact> bundled = <Fact>[
        _buildFact('a'),
        _buildFact('b'),
        _buildFact('c'),
      ];
      final RemoteCatalogue overlay = RemoteCatalogue(
        version: 1,
        // "b" is both a replacement candidate and marked as removed: removal
        // must win and "b" must not resurface via the append pass.
        facts: <Fact>[
          _buildFact('b', question: 'resurrected'),
          _buildFact('d'),
        ],
        removed: const <String>['b'],
      );

      final List<Fact> merged = mergeCatalogues(bundled, overlay);

      final List<String> ids = merged
          .map((Fact fact) => fact.id)
          .toList(growable: false);
      expect(ids, <String>['a', 'c', 'd']);
      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}
