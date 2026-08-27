import 'dart:convert';

import 'package:aja/core/config/contribution_config.dart';
import 'package:flutter/foundation.dart';

/// Why a contribution was refused before it ever left the device.
enum ContributionProblem {
  questionTooShort,
  questionTooLong,
  answerTooShort,
  answerTooLong,
}

/// A question and answer typed by a user on the "deck finished" screen.
///
/// Carries no identifier of any kind — no ad id, no install id, no device
/// model. That is a product decision, not an oversight: an anonymous suggestion
/// box keeps the Play Data Safety declaration at "user content, not linked to
/// identity", and there is nothing here worth tying to a person.
@immutable
class Contribution {
  const Contribution({
    required this.question,
    required this.answer,
    required this.source,
    required this.language,
    required this.createdAt,
  });

  factory Contribution.fromJson(Map<String, dynamic> json) => Contribution(
    question: json['question']! as String,
    answer: json['answer']! as String,
    source: json['source'] as String? ?? '',
    language: json['language'] as String? ?? 'es',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc(),
  );

  final String question;
  final String answer;

  /// Optional. Asked for anyway, because a suggestion that cites something is
  /// worth ten that do not: the catalogue's rule is that no fact ships without
  /// a source.
  final String source;

  /// UI language the contributor was reading in, so the text can be filed under
  /// the right column of the catalogue without guessing.
  final String language;

  final DateTime createdAt;

  /// Trims and validates. Returns the problems found, empty when it is fine.
  ///
  /// Runs before the outbox, not just before the network: garbage that is never
  /// sendable should not take up a slot for something real.
  static List<ContributionProblem> validate({
    required String question,
    required String answer,
  }) {
    final String q = question.trim();
    final String a = answer.trim();

    return <ContributionProblem>[
      if (q.length < ContributionConfig.minQuestionLength)
        ContributionProblem.questionTooShort,
      if (q.length > ContributionConfig.maxQuestionLength)
        ContributionProblem.questionTooLong,
      if (a.length < ContributionConfig.minAnswerLength)
        ContributionProblem.answerTooShort,
      if (a.length > ContributionConfig.maxAnswerLength)
        ContributionProblem.answerTooLong,
    ];
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'contribution',
    'question': question,
    'answer': answer,
    'source': source,
    'language': language,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  static Contribution decode(String raw) =>
      Contribution.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// What happened to a contribution the user just pressed send on.
enum ContributionResult {
  /// It reached the endpoint.
  sent,

  /// Kept in the on-device outbox: no endpoint configured yet, or the request
  /// failed. It goes out on the next flush, so from the user's side it counts.
  queued,

  /// Refused for coming too soon after the previous one.
  tooSoon,

  /// Refused by [Contribution.validate].
  invalid,
}
