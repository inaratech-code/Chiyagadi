import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/unified_database_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoading = false;
  bool _isFirstTime = false;
  bool _obscurePin = true;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    
    _animationController.forward();
    _checkFirstTime();
  }

  Future<void> _checkFirstTime() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    // Set context for AuthProvider to access UnifiedDatabaseProvider
    authProvider.setContext(context);
    
    final hasPin = await authProvider.checkPinExists();
    
    setState(() {
      _isFirstTime = !hasPin;
      if (_isFirstTime) {
        _usernameController.text = 'admin';
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_pinController.text.length < 4 || _pinController.text.length > 6) {
      setState(() {
        _errorMessage = 'PIN must be 4-6 digits';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get providers
      final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // Ensure context is set for database access
      authProvider.setContext(context);
      
      // Ensure database is initialized first with retry logic
      bool dbInitialized = false;
      int retryCount = 0;
      const maxRetries = 3;
      
      while (!dbInitialized && retryCount < maxRetries) {
        try {
          await dbProvider.init();
          // Verify database is actually working by trying a simple query
          try {
            await dbProvider.query('users', limit: 1);
            dbInitialized = true;
          } catch (queryError) {
            debugPrint('Database query test failed: $queryError');
            if (retryCount < maxRetries - 1) {
              // Try to reset and reinitialize
              try {
                await dbProvider.resetDatabase();
              } catch (resetError) {
                debugPrint('Database reset failed: $resetError');
              }
            }
            retryCount++;
          }
        } catch (initError) {
          debugPrint('Database initialization attempt ${retryCount + 1} failed: $initError');
          // Store the last error for display
          final lastError = initError.toString();
          if (retryCount < maxRetries - 1) {
            // Try to reset and reinitialize
            try {
              await dbProvider.resetDatabase();
            } catch (resetError) {
              debugPrint('Database reset failed: $resetError');
            }
          } else {
            // Last attempt failed - show detailed error
            setState(() {
              String errorDetails = 'Database initialization failed after $maxRetries attempts.\n\n';
              
              // Provide helpful error messages based on error type
              if (lastError.contains('permission') || lastError.contains('PERMISSION_DENIED')) {
                errorDetails += 'Error: Firestore security rules are blocking access.\n\n';
                errorDetails += 'Solution:\n';
                errorDetails += '1. Go to Firebase Console → Firestore Database → Rules\n';
                errorDetails += '2. Set rules to: allow read, write: if true;\n';
                errorDetails += '3. Click "Publish" (not just Save)';
              } else if (lastError.contains('not enabled') || lastError.contains('database')) {
                errorDetails += 'Error: Firestore Database is not enabled.\n\n';
                errorDetails += 'Solution:\n';
                errorDetails += '1. Go to Firebase Console → Firestore Database\n';
                errorDetails += '2. Click "Create database"\n';
                errorDetails += '3. Choose "Start in test mode"\n';
                errorDetails += '4. Select location and click "Enable"';
              } else {
                errorDetails += 'Error: $lastError\n\n';
                errorDetails += 'Please check:\n';
                errorDetails += '1. Browser console (F12) for detailed errors\n';
                errorDetails += '2. Firestore Database is enabled in Firebase Console\n';
                errorDetails += '3. Security rules are published';
              }
              
              _errorMessage = errorDetails;
              _isLoading = false;
            });
            return;
          }
          retryCount++;
        }
      }
      
      if (!dbInitialized) {
        // This shouldn't happen as we return above, but just in case
        setState(() {
          _errorMessage = 'Database initialization failed after $maxRetries attempts. Please check browser console (F12) for details.';
          _isLoading = false;
        });
        return;
      }
      
      final username = _usernameController.text.trim().isEmpty 
          ? 'admin' 
          : _usernameController.text.trim();

      if (_isFirstTime) {
        // Setup admin PIN
        try {
          final success = await authProvider.setupAdminPin(_pinController.text);
          if (success) {
            // Login after setup
            final loginSuccess = await authProvider.login('admin', _pinController.text);
            if (loginSuccess && mounted) {
              Navigator.of(context).pushReplacementNamed('/home');
            } else {
              setState(() {
                _errorMessage = 'Setup succeeded but login failed. Please try logging in.';
                _isLoading = false;
              });
            }
          } else {
            setState(() {
              _errorMessage = 'Setup failed. The database may be corrupted. Try resetting the database using the button below.';
              _isLoading = false;
            });
          }
        } catch (e) {
          setState(() {
            _errorMessage = 'Setup error: ${e.toString()}. Try resetting the database.';
            _isLoading = false;
          });
        }
      } else {
        // Regular login
        final success = await authProvider.login(username, _pinController.text);
        if (success && mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          setState(() {
            _errorMessage = 'Invalid username or PIN. Please try again.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFFFEB3B).withOpacity(0.3), // Light yellow (from logo)
              const Color(0xFFFFC107).withOpacity(0.4), // Golden yellow (from logo)
              const Color(0xFFFFB300).withOpacity(0.3), // Deeper golden
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Card(
                      elevation: 12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      shadowColor: Colors.black.withOpacity(0.2),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                            ],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(40.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Logo with animation
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 800),
                                curve: Curves.elasticOut,
                                builder: (context, value, child) {
                                  return Transform.scale(
                                    scale: value,
                                    child: Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            const Color(0xFFFFEB3B), // Light yellow center (from logo)
                                            const Color(0xFFFFC107), // Golden yellow edges (from logo)
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFC107).withOpacity(0.4),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: ClipOval(
                                        child: Image.asset(
                                          'assets/images/logo.jpeg',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.local_cafe,
                                              color: Color(0xFF8B4513), // Brown (from logo)
                                              size: 50,
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              // Café Name in Devanagari
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 600),
                                curve: Curves.easeOut,
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 10 * (1 - value)),
                                      child: Text(
                                        'चिया गढी',
                                        style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF8B4513),
                                          fontSize: 32,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              // English name
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 800),
                                curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 10 * (1 - value)),
                                      child: Text(
                                        'Chiya Gadhi',
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: Colors.grey[600],
                                          fontSize: 18,
                                          letterSpacing: 1.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              Container(
                                height: 1,
                                width: 60,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      const Color(0xFFFFC107).withOpacity(0.5),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 1000),
                                curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 10 * (1 - value)),
                                      child: Text(
                                        _isFirstTime 
                                            ? 'Setup Admin PIN' 
                                            : 'Welcome Back',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (_isFirstTime)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Enter a 4-6 digit PIN to get started',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[500],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              const SizedBox(height: 32),

                              // Username field (only for non-first-time)
                              if (!_isFirstTime) ...[
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 1100),
                                  curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.translate(
                                        offset: Offset(0, 20 * (1 - value)),
                                        child: TextField(
                                          controller: _usernameController,
                                          decoration: InputDecoration(
                                            labelText: 'Username',
                                            prefixIcon: const Icon(Icons.person_outline, color: Color(0xFFFFC107)),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: Colors.grey[300]!),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: Colors.grey[300]!),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: const BorderSide(color: Color(0xFFFFC107), width: 2),
                                            ),
                                            filled: true,
                                            fillColor: Colors.grey[50],
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                              ],

                              // PIN field
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 1200),
                                curve: Interval(_isFirstTime ? 0.5 : 0.67, 1.0, curve: Curves.easeOut),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 20 * (1 - value)),
                                      child: TextField(
                                        controller: _pinController,
                                        obscureText: _obscurePin,
                                        keyboardType: TextInputType.number,
                                        maxLength: 6,
                                        decoration: InputDecoration(
                                          labelText: 'PIN (4-6 digits)',
                                          prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFFC107)),
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePin ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                              color: Colors.grey[600],
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _obscurePin = !_obscurePin;
                                              });
                                            },
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(color: Colors.grey[300]!),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: const BorderSide(color: Color(0xFFFFC107), width: 2),
                                          ),
                                          filled: true,
                                          fillColor: Colors.grey[50],
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 20),

                              // Error message
                              if (_errorMessage != null)
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.0, end: 1.0),
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeOut,
                                  builder: (context, value, child) {
                                    return Opacity(
                                      opacity: value,
                                      child: Transform.scale(
                                        scale: 0.8 + (0.2 * value),
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 16),
                                          decoration: BoxDecoration(
                                            color: Colors.red[50],
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.red[200]!),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      _errorMessage!,
                                                      style: TextStyle(
                                                        color: Colors.red[900],
                                                        fontSize: 13,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              // Add "Create Admin" button if login fails and no admin exists
                                              if (_errorMessage!.contains('Invalid username or PIN') && !_isFirstTime)
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 8),
                                                  child: TextButton(
                                                    onPressed: _isLoading ? null : () async {
                                                      setState(() {
                                                        _isFirstTime = true;
                                                        _errorMessage = 'Please enter a new PIN to create admin account';
                                                        _pinController.clear();
                                                        _usernameController.text = 'admin';
                                                      });
                                                    },
                                                    child: const Text('Create New Admin Account'),
                                                  ),
                                                ),
                                              // Show reset button for setup failures or database errors
                                              if (_errorMessage!.contains('Setup failed') ||
                                                  _errorMessage!.contains('Setup error') ||
                                                  _errorMessage!.contains('DatabaseException') || 
                                                  _errorMessage!.contains('no such table') ||
                                                  _errorMessage!.contains('Reset failed') ||
                                                  (_errorMessage!.contains('Invalid username or PIN') && !_isFirstTime))
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 8),
                                                  child: Column(
                                                    children: [
                                                      TextButton(
                                                        onPressed: _isLoading ? null : () async {
                                                          setState(() {
                                                            _isLoading = true;
                                                            _errorMessage = 'Resetting database...';
                                                          });
                                                          
                                                          try {
                                                            final dbProvider = Provider.of<UnifiedDatabaseProvider>(context, listen: false);
                                                            
                                                            // Close database first
                                                            try {
                                                              await dbProvider.close();
                                                            } catch (_) {}
                                                            
                                                            // Reset database
                                                            await dbProvider.resetDatabase();
                                                            
                                                            // Clear SharedPreferences PIN
                                                            final prefs = await SharedPreferences.getInstance();
                                                            await prefs.remove('admin_pin');
                                                            
                                                            // Refresh first-time check
                                                            final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                                            authProvider.setContext(context);
                                                            final hasPin = await authProvider.checkPinExists();
                                                            
                                                            setState(() {
                                                              _errorMessage = 'Database reset successfully! Please set up your PIN again.';
                                                              _isFirstTime = !hasPin;
                                                              _pinController.clear();
                                                              _usernameController.text = 'admin';
                                                              _isLoading = false;
                                                            });
                                                          } catch (e) {
                                                            setState(() {
                                                              _errorMessage = 'Reset failed: ${e.toString()}\n\nTry uninstalling and reinstalling the app.';
                                                              _isLoading = false;
                                                            });
                                                          }
                                                        },
                                                        child: const Text('Reset Database'),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      TextButton(
                                                        onPressed: () {
                                                          setState(() {
                                                            _errorMessage = null;
                                                            _isLoading = false;
                                                          });
                                                        },
                                                        child: const Text('Clear Error', style: TextStyle(fontSize: 12)),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                              // Login button
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 1200),
                                curve: Interval(_isFirstTime ? 0.67 : 0.83, 1.0, curve: Curves.easeOut),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Transform.translate(
                                      offset: Offset(0, 20 * (1 - value)),
                                      child: Container(
                                        width: double.infinity,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          gradient: LinearGradient(
                                            colors: [
                                              const Color(0xFFFFC107), // Warm golden yellow (from logo)
                                              const Color(0xFFFFB300), // Deeper golden (from logo)
                                            ],
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFFFFC107).withOpacity(0.4),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _handleLogin,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.transparent,
                                            shadowColor: Colors.transparent,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 24,
                                                  height: 24,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                  ),
                                                )
                                              : Text(
                                                  _isFirstTime ? 'Setup & Login' : 'Login',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 24),
                              // Powered by Inara Tech
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 1200),
                                curve: const Interval(1.0, 1.0, curve: Curves.easeOut),
                                builder: (context, value, child) {
                                  return Opacity(
                                    opacity: value,
                                    child: Column(
                                      children: [
                                        Text(
                                          'Powered by',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Inara Tech',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF8B4513),
                                            letterSpacing: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pinController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
