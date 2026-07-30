import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shonenx/core/theme/shonenx_tokens.dart';
import 'package:shonenx/features/discovery/presentation/widgets/search/search_query_field.dart';
import 'package:shonenx/features/discovery/presentation/widgets/search/tv_onscreen_keyboard.dart';
import 'package:shonenx/shared/models/unified_media.dart';
import 'package:shonenx/shared/widgets/app_scaffold.dart';
import 'package:shonenx/source_engine/source_engine_provider.dart';

import 'widgets/discover/discover_tab_feed.dart';

/// Split search: query box and keyboard on the left, results on the right.
///
/// The previous version floated a `TextField` over a grid and relied on
/// hardware key characters being injected into it. That works with a keyboard
/// plugged in and not at all with a remote, and the autofocused field summoned
/// the leanback IME on arrival.
class SearchDiscoverScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  final MediaType type;
  final List<String> initialGenres;
  final List<String> initialTags;
  final String? source;

  const SearchDiscoverScreen({
    super.key,
    this.initialQuery,
    required this.type,
    this.initialGenres = const [],
    this.initialTags = const [],
    this.source,
  });

  @override
  ConsumerState<SearchDiscoverScreen> createState() =>
      _SearchDiscoverScreenState();
}

class _SearchDiscoverScreenState extends ConsumerState<SearchDiscoverScreen> {
  static const _debounce = Duration(milliseconds: 500);

  final FocusNode _firstKeyFocus = FocusNode(debugLabel: 'searchFirstKey');

  Timer? _debounceTimer;

  /// What the user has typed. [_query] lags it by [_debounce] and is what the
  /// search provider actually sees.
  String _text = '';
  String _query = '';

  List<String> _genres = [];
  List<String> _tags = [];
  String? _source;

  @override
  void initState() {
    super.initState();
    _text = widget.initialQuery?.trim() ?? '';
    _query = _text;
    _genres = List.from(widget.initialGenres);
    _tags = List.from(widget.initialTags);
    _source = widget.source;
  }

  @override
  void didUpdateWidget(SearchDiscoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _source = widget.source;
    if (oldWidget.initialQuery != widget.initialQuery) {
      _text = widget.initialQuery?.trim() ?? '';
      _query = _text;
    }
    if (oldWidget.initialGenres.join(',') != widget.initialGenres.join(',')) {
      _genres = List.from(widget.initialGenres);
    }
    if (oldWidget.initialTags.join(',') != widget.initialTags.join(',')) {
      _tags = List.from(widget.initialTags);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _firstKeyFocus.dispose();
    super.dispose();
  }

  void _setText(String next) {
    setState(() => _text = next);
    _debounceTimer?.cancel();

    final trimmed = next.trim();
    if (trimmed.isEmpty) {
      // Clearing should feel instant -- there is no request to coalesce.
      if (_query.isNotEmpty) setState(() => _query = '');
      return;
    }
    _debounceTimer = Timer(_debounce, () {
      if (mounted) setState(() => _query = trimmed);
    });
  }

  MediaType get _currentType {
    final supported = ref.read(metadataSourceProvider).supportedMediaTypes;
    if (supported.contains(widget.type)) return widget.type;
    return supported.isEmpty ? MediaType.ANIME : supported.first;
  }

  @override
  Widget build(BuildContext context) {
    final gutter = ShonenX.gutter(MediaQuery.sizeOf(context));

    return AppScaffold(
      // No app bar: the reference has none, and on a screen where the whole
      // left column is already a control surface a title row is dead space.
      fullBleed: true,
      body: Padding(
        padding: EdgeInsets.fromLTRB(gutter, gutter * 0.5, gutter, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: ShonenX.searchColumnWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SearchQueryField(text: _text),
                  const SizedBox(height: 24),
                  TvOnScreenKeyboard(
                    firstKeyFocus: _firstKeyFocus,
                    onChar: (c) => _setText(_text + c),
                    onSpace: () => _setText('$_text '),
                    onBackspace: () {
                      if (_text.isEmpty) return;
                      _setText(_text.substring(0, _text.length - 1));
                    },
                  ),
                ],
              ),
            ),
            SizedBox(width: gutter),
            Expanded(
              child: DiscoverTabFeed(
                // Rebuild the feed from scratch when the query changes so the
                // results list scrolls back to the top rather than holding a
                // stale offset into a different result set.
                key: ValueKey('$_query|${_genres.join(",")}|$_source'),
                type: _currentType,
                query: _query,
                genres: _genres,
                tags: _tags,
                source: _source,
                listMode: true,
                onGenreSelect: (g) => setState(() => _genres = [g]),
                onSourceSelect: (s) => setState(() => _source = s),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
