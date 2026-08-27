import 'package:aja/core/routing/app_routes.dart';
import 'package:aja/core/widgets/error_view.dart';
import 'package:aja/features/facts/presentation/screens/deck_screen.dart';
import 'package:aja/features/facts/presentation/screens/favorites_screen.dart';
import 'package:aja/features/goals/presentation/screens/progress_screen.dart';
import 'package:aja/features/premium/presentation/screens/paywall_screen.dart';
import 'package:aja/features/settings/presentation/screens/settings_screen.dart';
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
            const DeckScreen(),
        routes: <RouteBase>[
          GoRoute(
            path: 'settings',
            name: AppRoutes.settingsName,
            builder: (BuildContext context, GoRouterState state) =>
                const SettingsScreen(),
          ),
          GoRoute(
            path: 'favorites',
            name: AppRoutes.favoritesName,
            builder: (BuildContext context, GoRouterState state) =>
                const FavoritesScreen(),
          ),
          GoRoute(
            path: 'progress',
            name: AppRoutes.progressName,
            builder: (BuildContext context, GoRouterState state) =>
                const ProgressScreen(),
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
