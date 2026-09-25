import 'dart:io';

import 'package:chismosa/features/stories/data/story_share_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a story to the system share sheet as a 1080x1920 image plus a link.
///
/// The image is what gets posted; the link is what brings people back — to the
/// story's thread if they have the app, to Google Play if they do not.
class StoryShareService {
  bool _busy = false;

  /// Returns false when a share is already on screen. Two swipes in a row must
  /// not queue two sheets.
  Future<bool> share({
    required String storyId,
    required String body,
    required String cta,
    required String link,
    required String message,
    String? tag,
  }) async {
    if (_busy) return false;
    _busy = true;
    try {
      final List<int> png = await StoryShareImage.render(
        body: body,
        cta: cta,
        link: link.replaceFirst('https://', ''),
        tag: tag,
      );
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/chismosa_$storyId.png');
      await file.writeAsBytes(png, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          text: message,
        ),
      );
      return true;
    } finally {
      _busy = false;
    }
  }
}
