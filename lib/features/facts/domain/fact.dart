import 'package:flutter/foundation.dart';

/// Content buckets shown in the category filter.
///
/// A closed enum rather than a free string from the JSON: an unknown category
/// in the catalogue must fail loudly at parse time, not render an empty chip in
/// production.
enum FactCategory {
  body('cuerpo'),
  language('lenguaje'),
  history('historia'),
  science('ciencia');

  const FactCategory(this.id);

  /// Key used in `assets/data/facts.json`.
  final String id;

  static FactCategory fromId(String id) {
    return FactCategory.values.firstWhere(
      (FactCategory category) => category.id == id,
      orElse: () => throw FormatException('Unknown fact category: $id'),
    );
  }
}

/// A string that ships in every supported language inside the catalogue.
///
/// The content *is* the product, so it is localized in the asset instead of the
/// `.arb` files: translating it must not require a new app release, and the
/// same JSON will later come from Remote Config.
@immutable
class LocalizedText {
  const LocalizedText({required this.es, required this.en});

  factory LocalizedText.fromJson(Map<String, dynamic> json) =>
      LocalizedText(es: json['es']! as String, en: json['en']! as String);

  final String es;
  final String en;

  /// Falls back to Spanish, the language the catalogue is authored in.
  String resolve(String languageCode) => languageCode == 'en' ? en : es;
}

/// One question/answer card.
@immutable
class Fact {
  const Fact({
    required this.id,
    required this.category,
    required this.question,
    required this.answer,
    required this.detail,
    required this.source,
    required this.sourceUrl,
  });

  factory Fact.fromJson(Map<String, dynamic> json) => Fact(
    id: json['id']! as String,
    category: FactCategory.fromId(json['category']! as String),
    question: LocalizedText.fromJson(json['question']! as Map<String, dynamic>),
    answer: LocalizedText.fromJson(json['answer']! as Map<String, dynamic>),
    detail: LocalizedText.fromJson(json['detail']! as Map<String, dynamic>),
    source: json['source']! as String,
    sourceUrl: json['sourceUrl'] as String? ?? '',
  );

  /// Stable across releases: it is the persistence key for the deck position
  /// and, later, for favourites and share deep links.
  final String id;
  final FactCategory category;

  /// Front of the card.
  final LocalizedText question;

  /// Back of the card, first line.
  final LocalizedText answer;

  /// Back of the card, the 2–3 line explanation.
  final LocalizedText detail;

  /// Human readable citation. Never empty: a fact without a source does not
  /// ship.
  final String source;

  /// Permalink. Empty until the entry has been re-verified by hand.
  final String sourceUrl;
}
