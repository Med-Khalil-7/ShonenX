
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/features/onboarding/providers/onboarding_provider.dart';
import 'package:shonenx/features/settings/presentation/widgets/settings_ui_components.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';

class DebugSettingsScreen extends ConsumerWidget {
  const DebugSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Debug Settings',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 50),
        children: [
          SettingsSection(
            title: 'App State & Onboarding',
            children: [
              SettingsActionTile(
                icon: Icons.restart_alt_rounded,
                title: 'Reset Onboarding Status',
                subtitle: 'Mark onboarding as incomplete and launch screen',
                onTap: () {
                  ref.read(onboardingProvider.notifier).resetOnboarding();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Onboarding status reset!'),
                      action: SnackBarAction(
                        label: 'Launch Now',
                        onPressed: () => context.go('/onboarding'),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

          SettingsSection(
            title: 'UI Feedback',
            children: [
              SettingsActionTile(
                icon: Icons.notifications_none_outlined,
                title: 'Trigger Snackbar',
                subtitle: 'Show a floating snackbar with an action',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Debug Snackbar Triggered!'),
                      action: SnackBarAction(
                        label: 'Dismiss',
                        onPressed: () {},
                      ),
                    ),
                  );
                },
              ),
            ],
          ),

        ],
      ),
    );
  }
}
