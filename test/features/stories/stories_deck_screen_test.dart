/// The stories deck on screen: that each gesture does what the button next to
/// it does, and that the card only leaves when it should.
library;

import 'package:chismosa/core/config/backend_config.dart';
import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_theme.dart';
import 'package:chismosa/features/stories/data/story_repository.dart';
import 'package:chismosa/features/stories/domain/feed_query.dart';
import 'package:chismosa/features/stories/domain/story.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/features/stories/presentation/screens/compose_story_screen.dart';
import 'package:chismosa/features/stories/presentation/screens/stories_deck_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/billing/premium_controller.dart';
import 'package:chismosa/services/billing/premium_state.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

Story _story(String id) => Story(
  id: id,
  body: 'Historia $id, con longitud suficiente para el check del servidor.',
  category: StoryCategory.anything,
  lang: 'es',
  createdAt: DateTime.utc(2026, 8, 1),
  likesCount: 3,
  messagesCount: 2,
);

class _Repository implements StoryRepository {
  _Repository(this.catalogue);

  final List<Story> catalogue;
  final List<String> liked = <String>[];
  final List<String> joined = <String>[];

  @override
  Future<List<Story>> fetchFeed(
    FeedQuery query, {
    List<String> excludeIds = const <String>[],
    int limit = BackendConfig.feedPageSize,
  }) async {
    final Set<String> exclude = excludeIds.toSet();
    return catalogue
        .where((Story story) => !exclude.contains(story.id))
        .toList(growable: false);
  }

  @override
  Future<Story?> fetchStory(String id) async => null;

  @override
  Future<void> like(String storyId) async => liked.add(storyId);

  @override
  Future<void> unlike(String storyId) async => liked.remove(storyId);

  @override
  Future<void> joinThread(String storyId) async => joined.add(storyId);

  @override
  Future<void> report(String storyId, {String? reason}) async {}

  @override
  Future<String> publish({
    required String body,
    required StoryCategory category,
    required String lang,
    String? countryCode,
    String? groupId,
  }) async => 'new';
}

/// Premium, so the deck holds no ad slots and the AdMob SDK stays out of it.
class _AlwaysPremium extends PremiumController {
  @override
  Future<PremiumStatus> build() async =>
      const PremiumStatus(isPremium: true, storeAvailable: false);
}

/// Hosts the deck on its own router, so the compose route the button points at
/// resolves without pulling in the whole app.
class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final GoRouter _router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const StoriesDeckScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'compose',
            name: AppRoutes.composeName,
            builder: (BuildContext context, GoRouterState state) =>
                const ComposeStoryScreen(),
          ),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: _router,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
  );
}

void main() {
  late _Repository repository;

  Future<void> pump(WidgetTester tester, List<Story> catalogue) async {
    // Pinned to Spanish: the default test locale is `en`, and an unpinned one
    // would silently assert against the other set of strings.
    tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    repository = _Repository(catalogue);

    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        premiumControllerProvider.overrideWith(_AlwaysPremium.new),
        storyRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Host()),
    );
    await tester.pumpAndSettle();
  }

  /// Drags the top card far enough to commit, then lets the animation finish.
  Future<void> swipe(WidgetTester tester, Offset by) async {
    await tester.drag(find.text(_story('a').body), by);
    await tester.pumpAndSettle();
  }

  testWidgets('the top story is the one on screen', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a'), _story('b')]);
    expect(find.text(_story('a').body), findsOneWidget);
    expect(find.text(_story('b').body), findsOneWidget);
  });

  testWidgets('a rightward swipe likes the story and brings up the next', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a'), _story('b')]);
    await swipe(tester, const Offset(400, 0));

    expect(repository.liked, <String>['a']);
    expect(find.text(_story('a').body), findsNothing);
  });

  testWidgets('a leftward swipe passes without liking', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a'), _story('b')]);
    await swipe(tester, const Offset(-400, 0));

    expect(repository.liked, isEmpty);
    expect(find.text(_story('a').body), findsNothing);
  });

  testWidgets('a downward swipe is a second way to pass', (
    WidgetTester tester,
  ) async {
    // Two directions for the same action on purpose: a reader going fast
    // should not have to aim.
    await pump(tester, <Story>[_story('a'), _story('b')]);
    await swipe(tester, const Offset(0, 400));

    expect(repository.liked, isEmpty);
    expect(find.text(_story('a').body), findsNothing);
  });

  testWidgets('an upward swipe joins the thread and keeps the card', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a'), _story('b')]);
    await swipe(tester, const Offset(0, -400));

    expect(repository.joined, <String>['a']);
    // Coming back from a thread onto a different card would make the whole
    // trip feel like a mistake.
    expect(find.text(_story('a').body), findsOneWidget);
  });

  testWidgets('the like button does what the rightward swipe does', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a'), _story('b')]);
    await tester.tap(find.byTooltip('Me gusta'));
    await tester.pumpAndSettle();

    expect(repository.liked, <String>['a']);
  });

  testWidgets('running out offers writing before re-reading', (
    WidgetTester tester,
  ) async {
    await pump(tester, <Story>[_story('a')]);
    await swipe(tester, const Offset(-400, 0));

    expect(find.text('Por ahora no hay más chismes'), findsOneWidget);
    expect(find.text('Contar el mío'), findsOneWidget);
    expect(find.text('Volver a empezar'), findsOneWidget);
  });
}
