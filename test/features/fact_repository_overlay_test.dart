/// Unit tests for how [FactRepository] folds the remote overlay over the
/// bundled asset.
///
/// A minimal fake [AssetBundle] stands in for the real one so the fixture is
/// small and every field is under the test's control, instead of asserting
/// against the 87 hand-authored entries in the real asset.
library;

import 'dart:convert';

import 'package:aja/features/facts/data/fact_repository.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:aja/features/facts/domain/remote_catalogue.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serves a fixed JSON payload for [FactRepository.assetPath] and counts how
/// many times it was asked to load it, so tests can prove the repository
/// caches instead of re-reading the bundle on every call.
class _FakeAssetBundle extends AssetBundle {
  _FakeAssetBundle(this._facts);

  final List<Map<String, dynamic>> _facts;
  int loadCount = 0;

  @override
  Future<ByteData> load(String key) async {
    expect(key, FactRepository.assetPath);
    loadCount++;
    final String raw = jsonEncode(<String, dynamic>{'facts': _facts});
    final List<int> bytes = utf8.encode(raw);
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// A well-formed bundled-asset entry, as a decoded JSON map.
Map<String, dynamic> _entry(String id, {String category = 'cuerpo'}) {
  return <String, dynamic>{
    'id': id,
    'category': category,
    'question': <String, String>{'es': 'q $id', 'en': 'q $id'},
    'answer': <String, String>{'es': 'a $id', 'en': 'a $id'},
    'detail': <String, String>{'es': 'd $id', 'en': 'd $id'},
    'source': 's $id',
    'sourceUrl': '',
  };
}

Fact _buildFact(String id) {
  return Fact(
    id: id,
    category: FactCategory.body,
    question: LocalizedText(es: 'q $id', en: 'q $id'),
    answer: LocalizedText(es: 'a $id', en: 'a $id'),
    detail: LocalizedText(es: 'd $id', en: 'd $id'),
    source: 's $id',
    sourceUrl: '',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'with overlay null, the repository returns exactly the bundled facts',
    () async {
      final _FakeAssetBundle bundle = _FakeAssetBundle(<Map<String, dynamic>>[
        _entry('a'),
        _entry('b'),
      ]);
      final FactRepository repository = FactRepository(bundle: bundle);

      final List<Fact> facts = await repository.loadAll();

      expect(facts.map((Fact fact) => fact.id), <String>['a', 'b']);
    },
  );

  test(
    'with an overlay that adds a fact, loadAll returns bundled plus the new one',
    () async {
      final _FakeAssetBundle bundle = _FakeAssetBundle(<Map<String, dynamic>>[
        _entry('a'),
        _entry('b'),
      ]);
      final FactRepository repository = FactRepository(
        bundle: bundle,
        overlay: () async => RemoteCatalogue(
          version: 1,
          facts: <Fact>[_buildFact('c')],
          removed: const <String>[],
        ),
      );

      final List<Fact> facts = await repository.loadAll();

      expect(facts.map((Fact fact) => fact.id), <String>['a', 'b', 'c']);
    },
  );

  test(
    'an overlay callback that throws still yields the bundled catalogue',
    () async {
      // The most important test in this file: a broken remote layer — a bad
      // cache read, a network client that throws, whatever it is — must cost
      // the user nothing.
      final _FakeAssetBundle bundle = _FakeAssetBundle(<Map<String, dynamic>>[
        _entry('a'),
        _entry('b'),
      ]);
      final FactRepository repository = FactRepository(
        bundle: bundle,
        overlay: () async => throw StateError('remote cache is corrupt'),
      );

      final List<Fact> facts = await repository.loadAll();

      expect(facts.map((Fact fact) => fact.id), <String>['a', 'b']);
    },
  );

  test(
    'loadAll caches: calling it twice does not re-read the bundle',
    () async {
      final _FakeAssetBundle bundle = _FakeAssetBundle(<Map<String, dynamic>>[
        _entry('a'),
      ]);
      final FactRepository repository = FactRepository(bundle: bundle);

      final List<Fact> first = await repository.loadAll();
      final List<Fact> second = await repository.loadAll();

      expect(bundle.loadCount, 1);
      expect(identical(first, second), isTrue);
    },
  );
}
