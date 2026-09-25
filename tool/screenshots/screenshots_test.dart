/// Renders the main screens to PNG with real fonts, for design review and the
/// brand book. Not part of the test suite (it lives outside `test/`):
///
///   flutter test tool/screenshots/screenshots_test.dart --update-goldens
///
/// The images land in `tool/screenshots/goldens/`. Emoji (the country flags)
/// do not render here: the test engine has no emoji font.
// It is a test, just not one in test/, so the analyzer does not know that.
// ignore_for_file: invalid_use_of_visible_for_testing_member
library;

import 'dart:io';

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_theme.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/screens/my_stories_screen.dart';
import 'package:chismosa/features/stories/presentation/screens/stories_deck_screen.dart';
import 'package:chismosa/features/welcome/welcome_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/billing/premium_state.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final DateTime _now = DateTime.now().toUtc();

final List<Story> _stories = <Story>[
  Story(
    id: 'a',
    body:
        'Mi jefa lleva tres meses firmando los correos con el nombre de su '
        'perro. Nadie se lo ha dicho. Hoy el director le ha contestado '
        '«Gracias, Toby».',
    category: StoryCategory.work,
    lang: 'es',
    createdAt: _now.subtract(const Duration(hours: 2)),
    likesCount: 128,
    messagesCount: 42,
  ),
  Story(
    id: 'b',
    body:
        'La vecina del cuarto recibe un ramo de flores cada viernes. Hoy he '
        'visto al repartidor: es su marido, disfrazado.',
    category: StoryCategory.neighbours,
    lang: 'es',
    createdAt: _now.subtract(const Duration(minutes: 35)),
    likesCount: 51,
    messagesCount: 9,
    chapter: 2,
  ),
];

class _Repository implements StoryRepository {
  @override
  Future<List<Story>> fetchFeed(
    FeedQuery query, {
    List<String> excludeIds = const <String>[],
    int limit = BackendConfig.feedPageSize,
  }) async => _stories;

  @override
  Future<PublishStatus> publishStatus() async => const PublishStatus(
    postedToday: 0,
    dailyLimit: 1,
    credits: 0,
    isPremium: false,
  );

  @override
  Future<Story?> fetchStory(String id) async => null;

  @override
  Future<void> like(String storyId) async {}

  @override
  Future<void> unlike(String storyId) async {}

  @override
  Future<void> report(String storyId, {String? reason}) async {}

  @override
  Future<List<OwnStory>> myStories() async => <OwnStory>[
    OwnStory(
      id: 'm1',
      body:
          'Mi abuela tiene un novio de 82 años y la familia cree que va al '
          'bingo los jueves.',
      createdAt: _now.subtract(const Duration(hours: 5)),
      likesCount: 311,
      messagesCount: 87,
      hidden: false,
      chapter: 1,
      hasNext: false,
    ),
    OwnStory(
      id: 'm2',
      body: 'Actualización: la familia ya lo sabe. El bingo era real también.',
      createdAt: _now.subtract(const Duration(days: 2)),
      likesCount: 96,
      messagesCount: 23,
      hidden: false,
      chapter: 2,
      hasNext: true,
    ),
  ];

  @override
  Future<String> publish({
    required String body,
    required StoryCategory category,
    required String lang,
    String? countryCode,
    String? groupId,
    String? parentId,
  }) async => 'new';
}

class _Premium extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

Future<void> _loadFonts() async {
  // Walk up from the test engine binary to the SDK's font cache.
  Directory at = File(Platform.resolvedExecutable).parent;
  while (!Directory('${at.path}/material_fonts').existsSync()) {
    at = at.parent;
  }
  final String dir = '${at.path}/material_fonts';
  final FontLoader roboto = FontLoader('Roboto');
  for (final String file in <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    roboto.addFont(
      Future<ByteData>.value(
        ByteData.sublistView(File('$dir/$file').readAsBytesSync()),
      ),
    );
  }
  await roboto.load();
  final FontLoader icons = FontLoader('MaterialIcons')
    ..addFont(
      Future<ByteData>.value(
        ByteData.sublistView(
          File('$dir/materialicons-regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

void main() {
  setUpAll(_loadFonts);

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget screen, {
    bool dark = false,
    Future<void> Function(WidgetTester)? before,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        premiumControllerProvider.overrideWith(_Premium.new),
        storyRepositoryProvider.overrideWithValue(_Repository()),
      ],
    );
    addTearDown(container.dispose);

    final GoRouter router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.homePath,
          name: AppRoutes.homeName,
          builder: (BuildContext context, GoRouterState state) => screen,
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (before != null) await before(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('welcome', (WidgetTester tester) async {
    await shoot(tester, '1_welcome', const WelcomeScreen());
  });

  testWidgets('welcome gestures', (WidgetTester tester) async {
    await shoot(
      tester,
      '2_welcome_gestures',
      const WelcomeScreen(),
      before: (WidgetTester tester) async {
        await tester.tap(find.text('Siguiente'));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('deck light', (WidgetTester tester) async {
    await shoot(tester, '3_deck_light', const StoriesDeckScreen());
  });

  testWidgets('deck dark', (WidgetTester tester) async {
    await shoot(tester, '4_deck_dark', const StoriesDeckScreen(), dark: true);
  });

  testWidgets('my stories', (WidgetTester tester) async {
    await shoot(tester, '5_my_stories', const MyStoriesScreen());
  });
}
