import 'dart:typed_data';

import 'package:aja/features/facts/data/fact_story_image.dart';
import 'package:aja/features/facts/domain/fact.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a fact to the system share sheet as a ready-to-post 9:16 image.
///
/// Split from [FactStoryImage] so the artwork can be rendered and asserted on
/// in a test without a share sheet anywhere near it.
class FactShareService {
  const FactShareService();

  /// Shares the *question* only.
  ///
  /// The answer stays in the app on purpose: a post that gives it away is a
  /// post nobody has a reason to follow.
  Future<void> shareQuestion({
    required Fact fact,
    required String language,
    required FactStoryLabels labels,
    required String message,
  }) async {
    final Uint8List png = await FactStoryImage.render(
      fact: fact,
      language: language,
      labels: labels,
    );

    final String fileName = 'aja-${fact.id}.png';

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile.fromData(png, mimeType: 'image/png', name: fileName),
        ],
        // Bytes have no path for the platform side to name the temp file after,
        // and both Instagram and TikTok pick their importer from the extension.
        fileNameOverrides: <String>[fileName],
        text: message,
        subject: labels.appName,
      ),
    );
  }
}
