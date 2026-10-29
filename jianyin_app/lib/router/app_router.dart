import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_page.dart';
import '../features/auth/register_page.dart';
import '../features/history/history_page.dart';
import '../features/home/home_page.dart';
import '../features/membership/membership_page.dart';
import '../features/profile/profile_page.dart';
import '../features/settings/settings_page.dart';

abstract final class AppRoutes {
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const profile = '/profile';
  static const settings = '/settings';
  static const history = '/history';
  static const membership = '/membership';
}

/// 从右向左滑入（新页从右侧进入，旧页向左让出）。
CustomTransitionPage<void> _slideFromRight({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final secondaryCurved = CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0),
        ).animate(secondaryCurved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  routes: [
    GoRoute(
      path: AppRoutes.login,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const LoginPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.register,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const RegisterPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.home,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const HomePage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.profile,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const ProfilePage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const SettingsPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.history,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const HistoryPage(),
      ),
    ),
    GoRoute(
      path: AppRoutes.membership,
      pageBuilder: (context, state) => _slideFromRight(
        state: state,
        child: const MembershipPage(),
      ),
    ),
  ],
);
