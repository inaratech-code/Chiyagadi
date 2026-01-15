import 'package:flutter/material.dart';

/// Wrapper widget that removes AppBar from child screens
/// Used when screens are displayed within HomeScreen's navigation
class ScreenWrapper extends StatelessWidget {
  final Widget child;
  final bool hideAppBar;

  const ScreenWrapper({
    super.key,
    required this.child,
    this.hideAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    if (hideAppBar) {
      // If the child is a Scaffold, we need to extract its body
      if (child is Scaffold) {
        final scaffold = child as Scaffold;
        return Scaffold(
          body: scaffold.body,
          floatingActionButton: scaffold.floatingActionButton,
          drawer: scaffold.drawer,
          bottomNavigationBar: scaffold.bottomNavigationBar,
          backgroundColor: scaffold.backgroundColor,
          resizeToAvoidBottomInset: scaffold.resizeToAvoidBottomInset,
        );
      }
      return child;
    }
    return child;
  }
}
