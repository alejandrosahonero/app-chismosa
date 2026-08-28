/// Anything the card stack can render.
///
/// The stack does not care what a card *is* — a story, an ad slot, and
/// whatever comes next are all just a key and a builder to it. This interface
/// is the whole contract, which is what lets one gesture widget serve every
/// deck in the app instead of being copied per feature.
abstract interface class DeckCard {
  /// Unique within a deck. Used as the widget key, so that the stack cannot
  /// hand one card's element to another while cards are animating out — which
  /// would, for an ad slot, mean reusing an already-disposed `BannerAd`.
  String get key;
}
