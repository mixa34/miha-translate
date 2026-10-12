import 'package:flutter/material.dart';
import '/data.dart';
import '/messages/messages.i18n.dart' show MainMessages;
// Shown: data.dart's `AppTheme` enum is the saved theme preference.
import '/theme/app_theme.dart' show AppRadius, AppSpacing;
import '../../translate_keys.dart';

/// The codes of [names] whose name contains [query], case-insensitively.
///
/// Same rules as the original language search: matches are ordered by where
/// the query occurs in the name, so prefix matches come first; names matching
/// at the same position keep [names]' (alphabetical) order. An empty query
/// returns every code. Surrounding spaces in the query are ignored.
List<String> filterLanguages(Map<String, String> names, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return names.keys.toList();
  final matches = <(String, int, int)>[];
  var order = 0;
  names.forEach((code, name) {
    final at = name.toLowerCase().indexOf(q);
    if (at >= 0) matches.add((code, at, order));
    order++;
  });
  matches.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
  return [for (final match in matches) match.$1];
}

/// The recently used codes worth showing: known languages only, never
/// Autodetect, each once, most recent first.
List<String> recentLanguages(Iterable<String?> codes, Map<String, String> names) => [
      ...{
        for (final code in codes)
          if (code != null && code != 'auto' && names.containsKey(code)) code,
      },
    ];

/// Shows the language picker for [side] and returns the chosen language code,
/// or null if it was dismissed.
///
/// It only reads the current languages and the recently used ones; choosing
/// a language changes nothing until the caller acts on the result.
Future<String?> showLanguagePicker(BuildContext context, FromTo side) {
  final names = Map<String, String>.of(side == FromTo.from ? fromSelLangMap : toSelLangMap);
  final (last1, last2, last3) = lastUsed(side);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => LanguagePickerSheet(
      side: side,
      names: names,
      selected: side == FromTo.from ? fromLangVal : toLangVal,
      recent: recentLanguages([last1, last2, last3], names),
    ),
  );
}

/// The content of the language picker bottom sheet.
class LanguagePickerSheet extends StatefulWidget {
  /// Code -> localized name, in display order. Contains 'auto' (Autodetect)
  /// on the source side only.
  final Map<String, String> names;
  final FromTo side;
  final String selected;
  final List<String> recent;

  const LanguagePickerSheet({
    required this.side,
    required this.names,
    required this.selected,
    required this.recent,
    Key? key = TranslateKeys.languagePicker,
  }) : super(key: key);

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _offersAutodetect => widget.side == FromTo.from && widget.names.containsKey('auto');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final messages = i18n().main;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.sm),
          child: Semantics(
            header: true,
            namesRoute: true,
            child: Text(
              widget.side == FromTo.from ? messages.translate_from : messages.translate_to,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ),
      ),
      PinnedHeaderSliver(
        child: ColoredBox(
          color: theme.bottomSheetTheme.backgroundColor ?? theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
            child: TextField(
              key: TranslateKeys.languageSearch,
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: messages.search_languages,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
            ),
          ),
        ),
      ),
      if (_query.trim().isEmpty) ..._browse(messages) else ..._results(messages),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
    ];

    // The bottom sheet names its route with the generic "Dialog"; as the
    // innermost route, this one is named by the title instead, which screen
    // readers announce when the picker opens.
    //
    // Sits above the keyboard; without one, leaves a little of the screen
    // above the sheet visible.
    return Semantics(
      container: true,
      scopesRoute: true,
      explicitChildNodes: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: LayoutBuilder(
          builder: (context, constraints) => SizedBox(
            height: keyboard > 0 ? constraints.maxHeight : constraints.maxHeight * 0.9,
            child: CustomScrollView(slivers: slivers),
          ),
        ),
      ),
    );
  }

  List<Widget> _browse(MainMessages messages) {
    final all = [for (final code in widget.names.keys) if (code != 'auto') code];
    return [
      if (_offersAutodetect) SliverToBoxAdapter(child: _tile('auto')),
      if (widget.recent.isNotEmpty) ...[
        _header(messages.recent_languages),
        SliverList.builder(itemCount: widget.recent.length, itemBuilder: (_, i) => _tile(widget.recent[i])),
      ],
      _header(messages.all_languages),
      SliverList.builder(itemCount: all.length, itemBuilder: (_, i) => _tile(all[i])),
    ];
  }

  List<Widget> _results(MainMessages messages) {
    final names = _offersAutodetect ? widget.names : {
      for (final entry in widget.names.entries)
        if (entry.key != 'auto') entry.key: entry.value,
    };
    final results = filterLanguages(names, _query);
    if (results.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: Text(
                messages.no_languages_found,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ];
    }
    return [SliverList.builder(itemCount: results.length, itemBuilder: (_, i) => _tile(results[i]))];
  }

  Widget _header(String label) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xs),
          child: Semantics(
            header: true,
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
      );

  Widget _tile(String code) {
    final scheme = Theme.of(context).colorScheme;
    final selected = code == widget.selected;
    // Its own Material: a ListTile paints its tile colour as ink on the nearest
    // Material, and the sheet's would let the highlight show outside the
    // scrolling list (over the drag handle, or where the keyboard is).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(widget.names[code]!),
          leading: code == 'auto' ? const Icon(Icons.auto_awesome) : null,
          trailing: selected ? const Icon(Icons.check) : null,
          selected: selected,
          selectedColor: scheme.onSecondaryContainer,
          selectedTileColor: scheme.secondaryContainer,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.medium)),
          onTap: () => Navigator.of(context).pop(code),
        ),
      ),
    );
  }
}
