import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shonenx/core/tv/tv_metrics.dart';
import 'package:shonenx/core/utils/responsive.dart';
import 'package:shonenx/shared/providers/theme_prefs_provider.dart';

class AppScaffold extends ConsumerWidget {
  final String? title;
  final Widget? titleWidget;
  final bool extendBody;
  final String? subtitle;
  final PreferredSizeWidget? barBottom;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final bool centerTitle;
  final bool showBackButton;

  /// Set for surfaces that intentionally reach the panel edge, e.g. the video
  /// player. Everything else keeps the TV overscan inset.
  final bool fullBleed;

  const AppScaffold({
    super.key,
    this.title,
    this.titleWidget,
    this.extendBody = false,
    this.subtitle,
    this.barBottom,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.centerTitle = false,
    this.showBackButton = true,
    this.fullBleed = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final useGradients = ref.watch(
      themePrefsProvider.select((p) => p.useGradients),
    );
    final hasImage = ref.watch(
      themePrefsProvider.select((p) => p.customBackgroundImagePath != null),
    );
    final useNoiseOverlay = ref.watch(
      themePrefsProvider.select((p) => p.useNoiseOverlay),
    );

    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: (useGradients || hasImage || useNoiseOverlay)
          ? Colors.transparent
          : theme.scaffoldBackgroundColor,
      extendBody: extendBody,
      appBar: title == null && titleWidget == null && actions == null
          ? null
          : AppBar(
              title:
                  titleWidget ??
                  (title == null
                      ? null
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        )),
              bottom: barBottom,
              centerTitle: centerTitle,
              elevation: 0,
              scrolledUnderElevation: 0,
              forceMaterialTransparency: true,
              leading: showBackButton && context.canPop()
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new),
                      onPressed: () => context.pop(),
                    )
                  : null,
              actions: actions,
            ),
      // TVs overscan: a border strip of the framebuffer may never reach the
      // panel. SafeArea.minimum is exactly the right hook, and applying it
      // here covers every screen that uses AppScaffold.
      body: SafeArea(
        minimum: fullBleed
            ? EdgeInsets.zero
            : TvMetrics.of(context.responsive),
        child: body,
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
