/// Groups: the invite code survives however it is pasted, and picking a group
/// switches the deck to it.
library;

import 'package:chismosa/core/theme/app_theme.dart';
import 'package:chismosa/features/groups/data/group_repository.dart';
import 'package:chismosa/features/groups/domain/story_group.dart';
import 'package:chismosa/features/groups/presentation/providers/groups_providers.dart';
import 'package:chismosa/features/groups/presentation/screens/groups_screen.dart';
import 'package:chismosa/features/stories/presentation/providers/stories_providers.dart';
import 'package:chismosa/l10n/generated/app_localizations.dart';
import 'package:chismosa/services/storage/storage_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

StoryGroup _group(String id, String name, {bool owner = false}) => StoryGroup(
  id: id,
  name: name,
  memberCount: 3,
  isOwner: owner,
  inviteCode: 'a1b2c3d4e5f6',
  inviteExpiresAt: DateTime.now().add(const Duration(days: 3)),
);

class _Groups implements GroupRepository {
  _Groups(this.groups);

  final List<StoryGroup> groups;
  final List<String> joinedCodes = <String>[];

  @override
  Future<List<StoryGroup>> myGroups() async => groups;

  @override
  Future<String> create(String name) async {
    groups.insert(0, _group('new', name, owner: true));
    return 'new';
  }

  @override
  Future<String> joinByCode(String code) async {
    joinedCodes.add(normalizeInviteCode(code));
    if (normalizeInviteCode(code) != 'a1b2c3d4e5f6') {
      throw const GroupException(GroupFailure.invalidInvite);
    }
    return 'g1';
  }

  @override
  Future<void> leave(String groupId) async =>
      groups.removeWhere((StoryGroup group) => group.id == groupId);

  @override
  Future<void> delete(String groupId) => leave(groupId);

  @override
  Future<String> rotateInvite(String groupId) async => 'ffffffffffff';
}

void main() {
  group('normalizeInviteCode', () {
    test('accepts capitals and spaces', () {
      expect(normalizeInviteCode('  A1B2 C3D4 E5F6 '), 'a1b2c3d4e5f6');
    });

    test('digs the code out of a pasted invite message', () {
      expect(
        normalizeInviteCode(
          'Únete a «Primos» en Chismosa.\nCódigo: a1b2c3d4e5f6\n'
          'chismosa://app/join/a1b2c3d4e5f6',
        ),
        'a1b2c3d4e5f6',
      );
    });
  });

  test('a group row never needs an account id to be read', () {
    final StoryGroup group = StoryGroup.fromRow(<String, dynamic>{
      'id': 'g1',
      'name': 'Primos',
      'member_count': 6,
      'is_owner': true,
      'invite_code': 'a1b2c3d4e5f6',
      'invite_expires_at': '2026-01-01T00:00:00Z',
    });
    expect(group.memberCount, 6);
    expect(group.inviteExpired(DateTime.utc(2026, 1, 2)), isTrue);
  });

  group('GroupsScreen', () {
    late ProviderContainer container;
    late _Groups repository;

    Future<void> pump(WidgetTester tester, {String? inviteCode}) async {
      tester.platformDispatcher.localesTestValue = const <Locale>[Locale('es')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      repository = _Groups(<StoryGroup>[_group('g1', 'Primos')]);
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          groupRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);

      final GoRouter router = GoRouter(
        initialLocation: '/groups',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            name: 'deck',
            builder: (BuildContext context, GoRouterState state) =>
                const Text('deck'),
            routes: <RouteBase>[
              GoRoute(
                path: 'groups',
                builder: (BuildContext context, GoRouterState state) =>
                    GroupsScreen(inviteCode: inviteCode),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('picking a group switches the deck to it', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Primos'));
      await tester.pumpAndSettle();

      expect(container.read(feedQueryProvider).groupId, 'g1');
      expect(find.text('deck'), findsOneWidget);
    });

    testWidgets('an invite link fills in the code but waits for a tap', (
      WidgetTester tester,
    ) async {
      await pump(tester, inviteCode: 'a1b2c3d4e5f6');

      expect(find.text('a1b2c3d4e5f6'), findsOneWidget);
      expect(repository.joinedCodes, isEmpty);

      await tester.tap(find.text('Unirme'));
      await tester.pumpAndSettle();
      expect(repository.joinedCodes, <String>['a1b2c3d4e5f6']);
      expect(container.read(feedQueryProvider).groupId, 'g1');
    });
  });
}
