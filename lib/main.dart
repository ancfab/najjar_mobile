import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/current_user_avatar_controller.dart';
import 'services/session_service.dart';
import 'theme/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Startup auth gate: reads the persisted session (not just in-memory
  // state) before the first frame, so a relaunch after logout opens on
  // Login rather than briefly showing — or worse, staying on — an
  // authenticated screen.
  final isLoggedIn = await const SharedPreferencesSessionService().isLoggedIn();
  if (isLoggedIn) {
    // Restores the temporary local/mock avatar (see
    // CurrentUserAvatarController) so it's already in place on the first
    // authenticated frame instead of popping in after a rebuild.
    await currentUserAvatarController.restorePersisted();
  }
  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.isLoggedIn = false});

  /// Whether a previously-established session is still active, as
  /// determined by [SessionService.isLoggedIn] before the widget tree is
  /// built. Defaults to false (Login) so widget tests that construct
  /// MyApp() directly — bypassing main()'s async startup check — see the
  /// same behavior as a fresh, logged-out install.
  final bool isLoggedIn;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ANC Fabrics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryNavy,
          surface: AppColors.background,
        ),
      ),
      home: isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
