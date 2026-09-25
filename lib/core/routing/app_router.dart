import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/widgets/error_view.dart';
import 'package:chismosa/features/goals/presentation/screens/progress_screen.dart';
import 'package:chismosa/features/groups/presentation/screens/groups_screen.dart';
import 'package:chismosa/features/premium/presentation/screens/paywall_screen.dart';
import 'package:chismosa/features/settings/presentation/screens/language_preferences_screen.dart';
import 'package:chismosa/features/settings/presentation/screens/settings_screen.dart';
import 'package:chismosa/features/stories/presentation/screens/compose_story_screen.dart';
import 'package:chismosa/features/stories/presentation/screens/rules_screen.dart';
import 'package:chismosa/features/stories/presentation/screens/stories_deck_screen.dart';
import 'package:chismosa/features/threads/presentation/screens/thread_screen.dart';
import 'package:chismosa/features/threads/presentation/screens/threads_history_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Root navigator key.
///
/// Services that live outside the widget tree (ad callbacks, purchase stream)
/// need a context to show a dialog; they use this key instead of holding on to
/// a stale `BuildContext`.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root',
);

/// The application router.
///
/// Kept alive for the whole app lifetime on purpose: disposing it would reset
/// the navigation stack.
final Provider<GoRouter> routerProvider = Provider<GoRouter>((Ref ref) {
  final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.homePath,
    debugLogDiagnostics: false,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const StoriesDeckScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'settings',
            name: AppRoutes.settingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
          GoRoute(
            path: 'progress',
            name: AppRoutes.progressName,
            builder: (BuildContext context, GoRouterState state) =>
                const ProgressScreen(),
          ),
          GoRoute(
            path: 'compose',
            name: AppRoutes.composeName,
            builder: (BuildContext context, GoRouterState state) =>
                const ComposeStoryScreen(),
          ),
          GoRoute(
            path: 'threads',
            name: AppRoutes.threadsName,
            builder: (BuildContext context, GoRouterState state) =>
                const ThreadsHistoryScreen(),
          ),
          GoRoute(
            path: 'thread/:id',
            name: AppRoutes.threadName,
            builder: (BuildContext context, GoRouterState state) =>
                ThreadScreen(storyId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: 'rules',
            name: AppRoutes.rulesName,
            builder: (BuildContext context, GoRouterState state) =>
                const RulesScreen(),
          ),
          GoRoute(
            path: 'groups',
            name: AppRoutes.groupsName,
            builder: (BuildContext context, GoRouterState state) =>
                const GroupsScreen(),
          ),
          GoRoute(
            path: 'join/:code',
            name: AppRoutes.joinGroupName,
            builder: (BuildContext context, GoRouterState state) =>
                GroupsScreen(inviteCode: state.pathParameters['code']),
          ),
          GoRoute(
            path: 'languages',
            name: AppRoutes.languagesName,
            builder: (BuildContext context, GoRouterState state) =>
                const LanguagePreferencesScreen(),
          ),
          GoRoute(
            path: 'premium',
            name: AppRoutes.paywallName,
            builder: (BuildContext context, GoRouterState state) =>
                const PaywallScreen(),
          ),
        ],
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) =>
        RouteErrorScreen(location: state.uri.toString()),
  );

  ref.onDispose(router.dispose);
  return router;
});
