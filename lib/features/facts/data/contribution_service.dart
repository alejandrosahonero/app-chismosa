import 'dart:async';
import 'dart:convert';

import 'package:aja/core/config/contribution_config.dart';
import 'package:aja/core/utils/app_logger.dart';
import 'package:aja/features/facts/domain/contribution.dart';
import 'package:aja/services/storage/key_value_store.dart';
import 'package:http/http.dart' as http;

/// Collects what users send from the "deck finished" screen and forwards it to
/// [ContributionConfig.endpoint].
///
/// Everything is written to disk **before** anything is sent. The network is
/// treated as an optimization, never as the thing that decides whether the
/// user's action counted: a suggestion typed on the underground has to survive
/// the tunnel, and a tap on "ask for more" has to be counted even with the
/// endpoint still unconfigured.
class ContributionService {
  /// Positional store, matching [KeyValueStore]'s own shape in this codebase.
  ContributionService(this._store, {http.Client? client})
    : _client = client ?? http.Client();

  final KeyValueStore _store;

  /// Injectable so the upload path can be tested without a network.
  final http.Client _client;

  static const String _outboxKey = 'contrib_outbox';
  static const String _pendingTapsKey = 'contrib_more_taps_pending';
  static const String _totalTapsKey = 'contrib_more_taps_total';
  static const String _lastSubmitKey = 'contrib_last_submit_at';

  Timer? _flushTimer;

  /// Taps waiting to be sent. Read by nothing but tests and the flush itself.
  int get pendingMoreRequests => _store.getInt(_pendingTapsKey);

  /// Every "ask for more" tap this install has ever made, kept locally so the
  /// number survives a failed upload and is still there to look at on device.
  int get totalMoreRequests => _store.getInt(_totalTapsKey);

  int get outboxSize => _store.getStringList(_outboxKey).length;

  void dispose() {
    _flushTimer?.cancel();
    _client.close();
  }

  /// Validates, stores and tries to send one contribution.
  Future<ContributionResult> submit({
    required String question,
    required String answer,
    required String source,
    required String language,
  }) async {
    if (Contribution.validate(question: question, answer: answer).isNotEmpty) {
      return ContributionResult.invalid;
    }

    final DateTime? last = _store.getDateTime(_lastSubmitKey);
    if (last != null &&
        DateTime.now().toUtc().difference(last) <
            ContributionConfig.minIntervalBetweenContributions) {
      return ContributionResult.tooSoon;
    }

    final Contribution contribution = Contribution(
      question: question.trim(),
      answer: answer.trim(),
      source: source.trim(),
      language: language,
      createdAt: DateTime.now().toUtc(),
    );

    await _appendToOutbox(contribution);
    await _store.setDateTime(_lastSubmitKey, contribution.createdAt);

    // The rate limit and the outbox are already updated, so a failure here
    // costs the user nothing: the next flush picks it up.
    final bool flushed = await _flushOutbox();
    return flushed ? ContributionResult.sent : ContributionResult.queued;
  }

  /// One press of "ask for more".
  ///
  /// The button exists to be mashed, so the tap is counted on device
  /// immediately and the batch is sent once the user stops — one request for
  /// twenty hearts instead of twenty requests.
  Future<void> registerMoreRequest() async {
    await _store.setInt(_pendingTapsKey, pendingMoreRequests + 1);
    await _store.setInt(_totalTapsKey, totalMoreRequests + 1);

    _flushTimer?.cancel();
    _flushTimer = Timer(
      ContributionConfig.moreRequestFlushDelay,
      () => unawaited(flush()),
    );
  }

  /// Sends whatever is waiting. Safe to call at any time; does nothing when
  /// there is nothing pending or no endpoint yet.
  Future<void> flush() async {
    await _flushOutbox();
    await _flushMoreRequests();
  }

  Future<void> _appendToOutbox(Contribution contribution) async {
    final List<String> outbox = <String>[
      ..._store.getStringList(_outboxKey),
      contribution.encode(),
    ];

    // Drop from the front: if the endpoint has been down long enough to fill
    // this, the oldest suggestion is the least likely to still matter.
    final int overflow = outbox.length - ContributionConfig.maxOutboxSize;
    await _store.setStringList(
      _outboxKey,
      overflow > 0 ? outbox.sublist(overflow) : outbox,
    );
  }

  /// Returns true when the outbox ended up empty.
  Future<bool> _flushOutbox() async {
    if (!ContributionConfig.isConfigured) return false;

    List<String> outbox = _store.getStringList(_outboxKey);
    if (outbox.isEmpty) return true;

    // Sent one at a time and removed one at a time: a batch that fails halfway
    // would either lose the tail or send the head twice.
    for (final String raw in List<String>.of(outbox)) {
      final bool ok = await _post(jsonDecode(raw) as Map<String, dynamic>);
      if (!ok) return false;

      outbox = <String>[..._store.getStringList(_outboxKey)]..remove(raw);
      await _store.setStringList(_outboxKey, outbox);
    }

    return true;
  }

  Future<void> _flushMoreRequests() async {
    final int pending = pendingMoreRequests;
    if (pending == 0 || !ContributionConfig.isConfigured) return;

    // Zeroed only on success, so a lost request means the taps are sent with
    // the next batch rather than silently dropped.
    final bool ok = await _post(<String, dynamic>{
      'type': 'more_request',
      'count': pending,
    });
    if (ok) await _store.setInt(_pendingTapsKey, 0);
  }

  Future<bool> _post(Map<String, dynamic> payload) async {
    try {
      final http.Response response = await _client
          .post(
            Uri.parse(ContributionConfig.endpoint),
            // Not application/json on purpose: an Apps Script web app reads the
            // raw body either way, and text/plain is the one content type that
            // never triggers a CORS preflight if this ever runs on web.
            headers: const <String, String>{
              'Content-Type': 'text/plain;charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(ContributionConfig.requestTimeout);

      // Apps Script answers a successful POST with a 302 to the script output.
      return response.statusCode >= 200 && response.statusCode < 400;
    } on Object catch (error) {
      // Never rethrown: no user is waiting on this, and a suggestion box that
      // can take the app down is worse than one that is late.
      AppLogger.debug('Contribution upload failed: $error', name: 'contrib');
      return false;
    }
  }
}
