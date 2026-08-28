/// Hosts the inherited facts deck for the tests that still cover it.
///
/// The app's root route belongs to Chismosa's stories deck now. `features/facts`
/// is still on disk while the new deck is built out, so the tests that exercise
/// it mount it here instead of going through [App] — otherwise they would be
/// asserting against a completely different screen.
///
/// The routes it can navigate to are declared alongside it, so a tap on the
/// paywall pitch or the ring lands somewhere real rather than on the router's
/// error page.
library;

import 'package:chismosa/core/routing/app_router.dart';
import 'package:chismosa/core/routing/app_routes.dart';
import 'package:chismosa/core/theme/app_theme.dart';
import 'package:chismosa/features/facts/presentation/screens/deck_screen.dart';
import 'package:chismosa/features/facts/presentation/screens/favorites_screen.dart';
import 'package:chismosa/features/goals/presentation/screens/progress_screen.dart';
import 'package:chismosa/features/premium/presentation/screens/paywall_screen.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FactsDeckHost extends StatefulWidget {
  const FactsDeckHost({super.key});

  @override
  State<FactsDeckHost> createState() => _FactsDeckHostState();
}

class _FactsDeckHostState extends State<FactsDeckHost> {
  late final GoRouter _router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.homePath,
        name: AppRoutes.homeName,
        builder: (BuildContext context, GoRouterState state) =>
            const DeckScreen(),
        routes: <RouteBase>[
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
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
