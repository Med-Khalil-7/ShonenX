// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:anymex_extension_runtime_bridge/anymex_extension_runtime_bridge.dart'
    as bridge;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'package:shonenx/core/tv/tv_focusable.dart';
import 'package:shonenx/core/utils/snackbar_utils.dart';
import 'package:shonenx/features/extensions/providers/extension_service_provider.dart';
import 'package:shonenx/features/discovery/presentation/widgets/search/tv_onscreen_keyboard.dart';
import 'package:shonenx/shared/widgets/app_bottom_sheet.dart';
import 'package:shonenx/source_engine/source_registry.dart';

class ManageReposSheet extends ConsumerStatefulWidget {
  final String? managerId;
  final String? autoAddUrl;
  final String? autoAddType;
  final String? autoAddManager;

  const ManageReposSheet({
    super.key,
    this.managerId,
    this.autoAddUrl,
    this.autoAddType,
    this.autoAddManager,
  });

  @override
  ConsumerState<ManageReposSheet> createState() => _ManageReposSheetState();
}

class _ManageReposSheetState extends ConsumerState<ManageReposSheet> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _clipboardText;
  late String _selectedEngineId;

  @override
  void initState() {
    super.initState();

    if (widget.autoAddManager != null &&
        [
          'aniyomi',
          'mangayomi',
          'cloudstream',
          'kotatsu',
          'sora',
        ].contains(widget.autoAddManager)) {
      _selectedEngineId = widget.autoAddManager!;
    } else if (widget.autoAddUrl != null) {
      final lower = widget.autoAddUrl!.toLowerCase();
      if (lower.contains('cloudstream')) {
        _selectedEngineId = 'cloudstream';
      } else if (lower.contains('kotatsu'))
        _selectedEngineId = 'kotatsu';
      else if (lower.contains('sora'))
        _selectedEngineId = 'sora';
      else if (lower.contains('mangayomi'))
        _selectedEngineId = 'mangayomi';
      else
        _selectedEngineId =
            widget.managerId?.replaceAll('-desktop', '') ?? 'aniyomi';
    } else {
      _selectedEngineId =
          widget.managerId?.replaceAll('-desktop', '') ?? 'aniyomi';
    }

    if (![
      'aniyomi',
      'mangayomi',
      'cloudstream',
      'kotatsu',
      'sora',
    ].contains(_selectedEngineId)) {
      _selectedEngineId = 'aniyomi';
    }

    _checkClipboard();

    if (widget.autoAddUrl != null && widget.autoAddUrl!.isNotEmpty) {
      _controller.text = widget.autoAddUrl!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _addRepo());
    }
  }

  @override
  void dispose() {
    SnackbarUtils.dismissCurrent();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null &&
          (text.startsWith('http://') || text.startsWith('https://'))) {
        if (mounted) setState(() => _clipboardText = text);
      }
    } catch (_) {}
  }

  String? _parseRepoUrl(String input) {
    input = input.trim();
    if (input.isEmpty) return null;
    if (input.startsWith('https://github.com/') && input.contains('/blob/')) {
      return input
          .replaceFirst(
            'https://github.com/',
            'https://raw.githubusercontent.com/',
          )
          .replaceFirst('/blob/', '/');
    }
    if (!input.startsWith('http://') && !input.startsWith('https://')) {
      return 'https://$input';
    }
    return input;
  }

  void _showSnackBar(
    String message, {
    bool isError = false,
    bool isSuccess = false,
  }) {
    SnackbarUtils.show(
      context,
      message,
      isError: isError,
      isSuccess: isSuccess,
    );
  }

  /// Opens the in-app keyboard so a remote can type a URL without the
  /// system IME. Returns focus to the sheet when dismissed.
  Future<void> _editUrl() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _UrlEntryDialog(initial: _controller.text),
    );
    if (result != null) {
      _controller.text = result;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: result.length),
      );
    }
  }

  Future<void> _addRepo() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;

    final parsedUrl = _parseRepoUrl(url);
    if (parsedUrl == null) {
      _showSnackBar('Invalid repository URL.', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final adapter = ref.read(extensionAdapterProvider);
      bool added = false;

      // Anime only: there is no manga or novel side to this app any more.
      if (await adapter.addRepo(
        parsedUrl,
        _selectedEngineId,
        bridge.ItemType.anime,
      )) {
        added = true;
      }

      if (mounted) {
        if (added) {
          _controller.clear();
          // Invalidate so the UI rebuilds with fresh data
          ref.invalidate(activeExtReposProvider);
          ref.invalidate(availableAnimeSourcesProvider);
          _showSnackBar(
            'Repository added to ${_getEngineName(_selectedEngineId)} successfully!',
            isSuccess: true,
          );
        } else {
          _showSnackBar(
            'Failed to add repository or already exists.',
            isError: true,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removeRepo(String url, String managerId) async {
    setState(() => _isLoading = true);
    try {
      final adapter = ref.read(extensionAdapterProvider);
      final removed = await adapter.removeRepo(url, managerId);

      if (removed) {
        ref.invalidate(activeExtReposProvider);
        ref.invalidate(availableAnimeSourcesProvider);
        if (mounted) _showSnackBar('Repository removed');
      } else {
        if (mounted) {
          _showSnackBar('Failed to remove repository', isError: true);
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getEngineName(String id) {
    switch (id.replaceAll('-desktop', '')) {
      case 'mangayomi':
        return 'Mangayomi';
      case 'aniyomi':
        return 'Tachiyomi / Aniyomi';
      case 'cloudstream':
        return 'CloudStream';
      case 'kotatsu':
        return 'Kotatsu';
      case 'sora':
        return 'Sora';
      default:
        return id.toUpperCase();
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return AppBottomSheet(
      title: 'Manage Repositories',
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader(context, 'ADD NEW REPOSITORY'),

            // TARGET ENGINE DROPDOWN
            DropdownButtonFormField<String>(
              initialValue: _selectedEngineId,
              icon: Icon(Icons.expand_more_rounded, color: cs.primary),
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                labelText: 'Target Engine',
                labelStyle: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'aniyomi',
                  child: Text('Tachiyomi / Aniyomi'),
                ),
                DropdownMenuItem(value: 'mangayomi', child: Text('Mangayomi')),
                DropdownMenuItem(
                  value: 'cloudstream',
                  child: Text('CloudStream'),
                ),
                DropdownMenuItem(value: 'kotatsu', child: Text('Kotatsu')),
                DropdownMenuItem(value: 'sora', child: Text('Sora')),
              ],
              onChanged: _isLoading
                  ? null
                  : (val) {
                      if (val != null) setState(() => _selectedEngineId = val);
                    },
            ),
            const SizedBox(height: 12),

            // URL TEXT FIELD
            //
            // readOnly keeps Android TV's leanback IME from ever opening. It
            // takes over the whole screen and hands focus back unpredictably:
            // dismissing it left this field still holding Flutter focus, so
            // every later activation anywhere in the app re-summoned the
            // keyboard. Text is entered through the in-app D-pad keyboard
            // instead, which is what the rest of the TV UI already uses.
            // onTap never fires from a D-pad, so the field itself cannot open
            // the editor. TvFocusable maps ENTER to onTap, and the field is
            // taken out of the focus order so there is exactly one focus stop.
            TvFocusable(
              onTap: _isLoading ? null : _editUrl,
              borderRadius: BorderRadius.circular(16),
              child: IgnorePointer(
                child: ExcludeFocus(
                  child: TextField(
                    keyboardType:
                        TextInputType.none, // TV: never raise the system IME
                    controller: _controller,
                    readOnly: true,
                    showCursor: false,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.3,
                      ),
                      labelText: 'Repository URL',
                      labelStyle: TextStyle(color: cs.onSurfaceVariant),
                      prefixIcon: Icon(
                        Icons.link_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, _) {
                          return value.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear_rounded,
                                    color: cs.onSurfaceVariant,
                                  ),
                                  onPressed: _controller.clear,
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    enabled: !_isLoading,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // CLIPBOARD BANNER
            if (_clipboardText != null && !_isLoading) ...[
              InkWell(
                onTap: () {
                  _controller.text = _clipboardText!;
                  _controller.selection = TextSelection.fromPosition(
                    TextPosition(offset: _clipboardText!.length),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.secondary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.content_paste_rounded,
                        size: 18,
                        color: cs.secondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paste from clipboard',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _clipboardText!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              const SizedBox(height: 12),
            ],

            // SUBMIT BUTTON
            FilledButton.icon(
              onPressed: _isLoading ? null : _addRepo,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _isLoading
                  ? Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 8),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_download_rounded, size: 20),
              label: Text(
                _isLoading ? 'Adding...' : 'Add Repository',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // ACTIVE REPOSITORIES SECTION
            _buildSectionHeader(context, 'ACTIVE REPOSITORIES'),

            Obx(() {
              final bridgeManager = Get.find<bridge.ExtensionManager>();
              final allManagers = bridgeManager.managers;
              final List<(bridge.Repo, String)> reposWithManager = [];
              final urls = <String>{};

              for (final m in allManagers) {
                final mId = m.id.replaceAll('-desktop', '');
                final aRepos = m.getReposRx(bridge.ItemType.anime).value;
                final mRepos = m.getReposRx(bridge.ItemType.manga).value;
                final nRepos = m.getReposRx(bridge.ItemType.novel).value;
                for (final r in [...aRepos, ...mRepos, ...nRepos]) {
                  if (urls.add(r.url)) {
                    reposWithManager.add((r, r.managerId ?? mId));
                  }
                }
              }

              if (reposWithManager.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.folder_off_rounded,
                        size: 32,
                        color: cs.outline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No repositories added yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  child: Column(
                    children: reposWithManager.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final isLast = index == reposWithManager.length - 1;

                      final repo = item.$1;
                      final mId = item.$2;
                      final uri = Uri.tryParse(repo.url);
                      final hostname = uri?.host ?? 'Custom Repo';

                      return Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              repo.name ?? hostname,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                _buildBadge(
                                  context,
                                  _getEngineName(mId).toUpperCase(),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  repo.url,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                color: cs.error,
                              ),
                              tooltip: 'Remove Repository',
                              onPressed: () => _removeRepo(repo.url, mId),
                            ),
                          ),
                          if (!isLast)
                            Divider(
                              height: 1,
                              indent: 72,
                              endIndent: 16,
                              color: cs.outlineVariant.withValues(alpha: 0.3),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// D-pad text entry for the repository URL.
///
/// Uses the app's own on-screen keyboard rather than the platform IME, plus a
/// row of the characters a URL needs that a plain alphanumeric keyboard has no
/// keys for.
class _UrlEntryDialog extends StatefulWidget {
  final String initial;

  const _UrlEntryDialog({required this.initial});

  @override
  State<_UrlEntryDialog> createState() => _UrlEntryDialogState();
}

class _UrlEntryDialogState extends State<_UrlEntryDialog> {
  late String _text = widget.initial;
  final _firstKeyFocus = FocusNode(debugLabel: 'urlFirstKey');

  static const _symbols = ['.', '/', ':', '-', '_', '~', '?', '='];

  @override
  void dispose() {
    _firstKeyFocus.dispose();
    super.dispose();
  }

  void _append(String s) => setState(() => _text += s);

  void _backspace() {
    if (_text.isEmpty) return;
    setState(() => _text = _text.substring(0, _text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // The keyboard sizes its keys from the height it is actually given;
    // devices report very different logical viewports for the same panel.
    final keyHeight =
        (MediaQuery.sizeOf(context).height * 0.42) /
        TvOnScreenKeyboard.rowCount;

    return AlertDialog(
      title: const Text('Repository URL'),
      content: SizedBox(
        width: 900,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _text.isEmpty ? 'https://…' : _text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _text.isEmpty ? cs.onSurfaceVariant : cs.onSurface,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sym in _symbols)
                  OutlinedButton(
                    onPressed: () => _append(sym),
                    child: Text(sym),
                  ),
                OutlinedButton(
                  onPressed: () => _append('https://'),
                  child: const Text('https://'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TvOnScreenKeyboard(
              keyHeight: keyHeight,
              firstKeyFocus: _firstKeyFocus,
              onChar: _append,
              onBackspace: _backspace,
              onSpace: () => _append(' '),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.trim()),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
