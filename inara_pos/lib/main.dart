import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
          create: (_) => InaraAuthProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => SyncProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'चिया गढी',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            scaffoldMessengerKey: AppMessenger.messengerKey,
            navigatorKey: AppMessenger.navigatorKey,
            home: const _WarmStart(child: AuthWrapper()),
            routes: {
              // IMPORTANT: provide an explicit root route so logout/login can
              // reliably reset navigation back to AuthWrapper.
              '/': (context) => const _WarmStart(child: AuthWrapper()),
              '/home': (context) => const HomeScreen(),
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

    // Run after first frame paint.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Warm up DB (and Firebase on web via UnifiedDatabaseProvider).
      try {
        final dbProvider = context.read<UnifiedDatabaseProvider>();
        await dbProvider.init();
        
        // Add admin user with specific document ID if on web
        if (kIsWeb) {
          final authProvider = context.read<InaraAuthProvider>();
          // Add admin user with document ID: dSc8mQzHPsftOpqb200d7xPhS7K2
          await addAdminUserWithId(
            dbProvider,
            authProvider,
            'dSc8mQzHPsftOpqb200d7xPhS7K2',
            username: 'admin',
            pin: 'Chiyagadi15@', // Admin password
            email: 'chiyagadi@gmail.com', // Admin email
          );
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NEW: "Ask password every time" option.
    // If lockMode == 'always', we lock the app when it goes to background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final auth = context.read<InaraAuthProvider>();
      if (auth.lockMode == 'always') {
        auth.logout();
      }
    }
  }

  Future<void> _checkAuth() async {
    // PERF: Show UI immediately, load preferences in background
    setState(() {
      _isLoading = false;
    });

    // Check Firebase Auth state
    try {
      final auth = FirebaseAuth.instance;
          final authProvider = context.read<InaraAuthProvider>();
      
      // Load lock mode preference (non-blocking)
      if (mounted) {
        authProvider.loadLockMode().catchError((e) {
          debugPrint('Error loading lock mode: $e');
        });
      }
      
      // If user is already signed in with Firebase Auth, restore session
      if (auth.currentUser != null && mounted) {
        debugPrint('AuthWrapper: Firebase Auth user already signed in: ${auth.currentUser!.email}');
        // Restore session by calling login (which will connect to Firestore document)
        final email = auth.currentUser!.email;
        if (email != null) {
          // We need to get the password from somewhere or skip password check
          // For now, just set authenticated state based on Firestore document
          try {
            final dbProvider = context.read<UnifiedDatabaseProvider>();
            await dbProvider.init();
            
            const adminDocumentId = 'dSc8mQzHPsftOpqb200d7xPhS7K2';
            final adminUsers = await dbProvider.query(
              'users',
              where: 'documentId = ?',
              whereArgs: [adminDocumentId],
            );
            
            if (adminUsers.isNotEmpty) {
              final adminUser = adminUsers.first;
              final adminEmail = adminUser['email'] as String?;
              
              if (adminEmail?.toLowerCase() == email.toLowerCase()) {
                authProvider.setContext(context);
                // Manually set authenticated state
                // Note: This bypasses password check, but user is already authenticated via Firebase Auth
                debugPrint('AuthWrapper: Restoring admin session for $email');
                // We'll let the AuthProvider handle this through its login method
                // For now, just ensure context is set
              }
            }
          } catch (e) {
            debugPrint('AuthWrapper: Error restoring session: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking Firebase Auth: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

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
