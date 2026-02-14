import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'providers/auth_provider.dart' show InaraAuthProvider;
import 'providers/unified_database_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'utils/app_messenger.dart';
import 'utils/theme.dart';
import 'utils/add_admin_user.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait mode (disable auto-rotation)
  // Only apply on mobile platforms (not web)
  if (!kIsWeb) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Global error handler to catch all unhandled errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exception}');
    debugPrint('Stack: ${details.stack}');
  };

  // CRITICAL: Do not block first frame on Firebase/DB init.
  // We warm these up asynchronously after the UI is on screen.
  final databaseProvider = UnifiedDatabaseProvider();
  runApp(InaraPOSApp(databaseProvider: databaseProvider));
}

class InaraPOSApp extends StatelessWidget {
  final UnifiedDatabaseProvider databaseProvider;
  const InaraPOSApp({super.key, required this.databaseProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: databaseProvider),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (context) => InaraAuthProvider(
            databaseProvider: context.read<UnifiedDatabaseProvider>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return Consumer<InaraAuthProvider>(
            builder: (context, authProvider, _) {
              // Key forces MaterialApp to rebuild when auth changes (fixes logout on web).
              return MaterialApp(
                key: ValueKey<bool>(authProvider.isAuthenticated),
                title: 'चिया गढी',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: themeProvider.themeMode,
                scaffoldMessengerKey: AppMessenger.messengerKey,
                navigatorKey: AppMessenger.navigatorKey,
                home: const _WarmStart(child: AuthWrapper()),
              );
            },
          );
        },
      ),
    );
  }
}

/// Starts slow initialization after the first frame so the app shows UI instantly.
class _WarmStart extends StatefulWidget {
  final Widget child;
  const _WarmStart({required this.child});

  @override
  State<_WarmStart> createState() => _WarmStartState();
}

class _WarmStartState extends State<_WarmStart> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Run after first frame paint - don't block UI.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final dbProvider = context.read<UnifiedDatabaseProvider>();
        await dbProvider.init();

        // PERF: Defer admin check so app feels instant. Run 1.5s after first paint.
        if (kIsWeb) {
          final authProvider = context.read<InaraAuthProvider>();
          Future.delayed(const Duration(milliseconds: 1500), () async {
            try {
              const adminDocumentId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
              final existing = await dbProvider.query(
                'users',
                where: 'documentId = ?',
                whereArgs: [adminDocumentId],
              );
              if (existing.isEmpty) {
                await addAdminUserWithId(
                  dbProvider,
                  authProvider,
                  adminDocumentId,
                  username: 'admin',
                  pin: 'Chiyagadi15@',
                  email: 'chiyagadi@gmail.com',
                );
                debugPrint('Main: Created admin user: $adminDocumentId');
              }
            } catch (e) {
              debugPrint('Main: Error creating admin user: $e');
            }
          });
        }
      } catch (e) {
        debugPrint('WarmStart: DB init failed: $e');
        if (kIsWeb) {
          debugPrint(
              'WarmStart: Firebase/Firestore is required for web. Please configure Firebase.');
          debugPrint('WarmStart: Run: flutterfire configure');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  InaraAuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // PERF: Check auth in background without blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuth();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Register logout callback so AuthWrapper rebuilds when logout() is called (fixes web).
    final authProvider = context.read<InaraAuthProvider>();
    if (_authProvider != authProvider) {
      _authProvider?.onLogout = null;
      _authProvider = authProvider;
      _authProvider!.onLogout = () {
        if (mounted) setState(() {});
      };
    }
  }

  @override
  void dispose() {
    _authProvider?.onLogout = null;
    _authProvider = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save last activity when app goes to background (for "Ask after long inactivity" 12h grace)
    if ((state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused) &&
        mounted) {
      final authProvider = context.read<InaraAuthProvider>();
      if (authProvider.isAuthenticated) {
        authProvider.saveLastActivityTimestamp();
      }
    }
  }

  Future<void> _checkAuth() async {
    // PERF: All auth checks run in background, UI shows immediately
    try {
      final auth = FirebaseAuth.instance;
      final authProvider = context.read<InaraAuthProvider>();

      await authProvider.loadLockMode();

      if (auth.currentUser != null && mounted) {
        authProvider.setContext(context);

        // Security: "Ask password every time" or "Ask after long inactivity" (12h expired)
        final requireLogin = await authProvider.shouldRequireLoginOnStart();
        if (requireLogin && mounted) {
          await auth.signOut();
          authProvider.onLogout?.call();
          debugPrint(
              'AuthWrapper: Lock mode requires login on start, signed out');
          return;
        }

        debugPrint(
            'AuthWrapper: Firebase Auth user signed in, restoring session: ${auth.currentUser!.email}');
        final restored = await authProvider.restoreSessionFromFirebaseUser(
            auth.currentUser!);
        if (restored && mounted) {
          debugPrint('AuthWrapper: Session restored successfully');
        } else if (!restored && mounted) {
          debugPrint(
              'AuthWrapper: Could not restore session (user not in DB or disabled)');
        }
      }
    } catch (e) {
      debugPrint('Error checking Firebase Auth: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // PERF: Show UI immediately without loading spinner
    return Consumer<InaraAuthProvider>(
      builder: (context, authProvider, _) {
        // IMPORTANT: keep a stable, long-lived context in AuthProvider so it can safely
        // access other providers (UnifiedDatabaseProvider) even if LoginScreen is disposed.
        authProvider.setContext(context);
        if (authProvider.isAuthenticated) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// Web platform not fully supported - show message
class WebNotSupportedScreen extends StatelessWidget {
  const WebNotSupportedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Colors.orange,
              ),
              const SizedBox(height: 24),
              Text(
                'Web Platform Limited Support',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'InaraPOS is designed for Android and iOS platforms.\n'
                'SQLite database is not available on web browsers.\n\n'
                'For full functionality, please use:',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.android),
                        title: const Text('Android'),
                        subtitle: const Text(
                            'Build APK and install on Android device'),
                      ),
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.phone_iphone),
                        title: const Text('iOS (PWA)'),
                        subtitle:
                            const Text('Build web version and install as PWA'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  // Still show login screen for UI testing
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text('Continue Anyway (UI Testing Only)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
