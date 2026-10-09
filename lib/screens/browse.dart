import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import '../xtream.dart';
import 'player.dart';
import 'series.dart';

const _favId = '*fav';
const _searchId = '*search';
const _allId = '*all';

String kindTitle(XKind kind) {
  switch (kind) {
    case XKind.live:
      return 'Live TV';
    case XKind.vod:
      return 'Movies';
    case XKind.series:
      return 'Series';
  }
}

/// Categories on the left, channels / titles on the right.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.api, required this.kind});

  final XtreamApi api;
  final XKind kind;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<XCategory>? _cats;
  String? _catsError;
  String _selected = '';
  String _selectedName = '';
  List<XItem>? _items;
  String? _itemsError;
  final Map<String, List<XItem>> _cache = {};
  List<XItem>? _all;
  String _query = '';
  int _request = 0;
  Timer? _focusTimer;

  bool get _live => widget.kind == XKind.live;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() {
      _cats = null;
      _catsError = null;
    });
    try {
      final cats = await widget.api.categories(widget.kind);
      if (!mounted) return;
      setState(() => _cats = cats);
      log('browse ${widget.kind.name} categories=${cats.length}');
      if (cats.isNotEmpty) {
        _select(cats.first.id, cats.first.name);
      } else {
        _select(_allId, 'All');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _catsError = friendlyError(e));
    }
  }

  Future<List<XItem>> _loadAll() async => _all ??= await widget.api.items(widget.kind);

  Future<void> _select(String id, String name) async {
    _focusTimer?.cancel();
    if (id == _selected && _items != null && id != _favId) return;
    final request = ++_request;
    final ready = id == _favId ? List<XItem>.of(Store.favourites(widget.kind)) : _cache[id];
    setState(() {
      _selected = id;
      _selectedName = name;
      _itemsError = null;
      _items = ready;
    });
    if (ready != null) {
      if (id == _favId) log('browse ${widget.kind.name} favourites=${ready.length}');
      return;
    }
    try {
      List<XItem> items;
      if (id == _allId) {
        items = await _loadAll();
      } else {
        items = await widget.api.items(widget.kind, categoryId: id);
        // Some servers ignore the category filter and send everything.
        if (items.any((i) => i.categoryId == id) && items.any((i) => i.categoryId != id)) {
          items = items.where((i) => i.categoryId == id).toList();
        }
      }
      _cache[id] = items;
      if (!mounted || request != _request) return;
      setState(() => _items = items);
      log('browse ${widget.kind.name} items=${items.length}');
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _itemsError = friendlyError(e));
    }
  }

  /// Moving over a category shows its content after a short pause, so the
  /// list can be skimmed without pressing OK on every row.
  void _focusCategory(String id, String name) {
    _focusTimer?.cancel();
    if (id == _selected) return;
    _focusTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _select(id, name);
    });
  }

  Future<void> _search() async {
    _focusTimer?.cancel();
    final q = await _askSearch(context, _query);
    if (q == null || q.isEmpty || !mounted) return;
    final request = ++_request;
    setState(() {
      _query = q;
      _selected = _searchId;
      _selectedName = 'Search: $q';
      _items = null;
      _itemsError = null;
    });
    try {
      final all = await _loadAll();
      if (!mounted || request != _request) return;
      final needle = q.toLowerCase();
      final found = all.where((i) => i.name.toLowerCase().contains(needle)).take(400).toList();
      setState(() => _items = found);
      log('browse ${widget.kind.name} search=${found.length}');
    } catch (e) {
      if (!mounted || request != _request) return;
      setState(() => _itemsError = friendlyError(e));
    }
  }

  void _retryItems() {
    final id = _selected;
    final name = _selectedName;
    if (id == _searchId) {
      _search();
      return;
    }
    _selected = '';
    _select(id, name);
  }

  void _toggleFavourite(XItem item) {
    final added = Store.toggleFavourite(item);
    log('favourite ${added ? 'added' : 'removed'}');
    setState(() {
      if (_selected == _favId) _items = List<XItem>.of(Store.favourites(widget.kind));
    });
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        width: 320,
        content: Text(added ? 'Added to Favourites' : 'Removed from Favourites', textAlign: TextAlign.center),
      ));
  }

  Future<void> _openItem(List<XItem> items, int index) async {
    final api = widget.api;
    final item = items[index];
    if (widget.kind == XKind.series) {
      await Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => SeriesScreen(api: api, series: item)));
    } else if (_live) {
      final first = Store.liveFormat;
      final second = first == 'ts' ? 'm3u8' : 'ts';
      final entries = [
        for (final i in items)
          PlayEntry(
            title: i.name,
            urls: [api.liveUrl(i.id, first), api.liveUrl(i.id, second)],
            epgId: i.id,
            logo: i.icon,
            item: i,
          ),
      ];
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PlayerScreen(api: api, entries: entries, index: index, live: true)));
    } else {
      final entries = [
        PlayEntry(title: item.name, urls: [api.vodUrl(item.id, item.ext)], resumeKey: 'vod:${item.id}', item: item),
      ];
      await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PlayerScreen(api: api, entries: entries, index: 0, live: false)));
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 236,
            color: C.panel,
            padding: const EdgeInsets.fromLTRB(12, 18, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 12),
                  child: Row(
                    children: [
                      const Logo(size: 18),
                      const SizedBox(width: 10),
                      Text(kindTitle(widget.kind), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
                Expanded(child: _categories()),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _selectedName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (_items != null)
                          Text('${_items!.length}', style: const TextStyle(color: C.dim, fontSize: 14)),
                      ],
                    ),
                  ),
                  Expanded(child: _content()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categories() {
    if (_catsError != null) return ErrorBox(message: _catsError!, onRetry: _loadCategories, autofocus: true);
    final cats = _cats;
    if (cats == null) return const Loading();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: cats.length + 2,
      itemExtent: 42,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _CategoryRow(
            icon: Icons.search_rounded,
            name: 'Search',
            selected: _selected == _searchId,
            onTap: _search,
          );
        }
        if (index == 1) {
          return _CategoryRow(
            icon: Icons.star_rounded,
            name: 'Favourites',
            selected: _selected == _favId,
            autofocus: cats.isEmpty,
            onTap: () => _select(_favId, 'Favourites'),
            onFocus: () => _focusCategory(_favId, 'Favourites'),
          );
        }
        final cat = cats[index - 2];
        return _CategoryRow(
          name: cat.name,
          selected: _selected == cat.id,
          autofocus: index == 2,
          onTap: () => _select(cat.id, cat.name),
          onFocus: () => _focusCategory(cat.id, cat.name),
        );
      },
    );
  }

  Widget _content() {
    if (_itemsError != null) return ErrorBox(message: _itemsError!, onRetry: _retryItems);
    final items = _items;
    if (items == null) {
      return _cats == null && _catsError != null ? const SizedBox() : const Loading();
    }
    if (items.isEmpty) {
      final text = _selected == _favId
          ? 'No favourites yet.\nHold OK on a ${_live ? 'channel' : 'title'} to add it here.'
          : (_selected == _searchId ? 'Nothing found.' : 'This category is empty.');
      return Center(
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: C.dim, fontSize: 15, height: 1.5)),
      );
    }
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      final int columns;
      final double extent;
      if (_live) {
        columns = math.max(1, (width / 222).floor());
        extent = 58;
      } else {
        columns = math.max(2, (width / 128).floor());
        extent = ((width - (columns - 1) * 10) / columns) * 1.48;
      }
      return GridView.builder(
        key: ValueKey('$_selected|$_query'),
        padding: const EdgeInsets.fromLTRB(2, 2, 2, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: extent,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final fav = Store.isFavourite(item);
          void open() => _openItem(items, index);
          void hold() => _toggleFavourite(item);
          return _live
              ? _ChannelTile(item: item, number: index + 1, favourite: fav, onTap: open, onLongPress: hold)
              : _PosterTile(item: item, favourite: fav, onTap: open, onLongPress: hold);
        },
      );
    });
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.name,
    required this.selected,
    required this.onTap,
    this.onFocus,
    this.icon,
    this.autofocus = false,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TvFocus(
        autofocus: autofocus,
        selected: selected,
        color: C.panel,
        radius: 8,
        onTap: onTap,
        onFocus: onFocus,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: C.accent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? C.text : const Color(0xFFC9CFDA),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.item,
    required this.number,
    required this.favourite,
    required this.onTap,
    required this.onLongPress,
  });

  final XItem item;
  final int number;
  final bool favourite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: [
            SizedBox(width: 40, height: 40, child: NetImage(item.icon, cacheWidth: 96)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w600),
              ),
            ),
            if (favourite) const Icon(Icons.star_rounded, color: C.accent, size: 15),
          ],
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.item,
    required this.favourite,
    required this.onTap,
    required this.onLongPress,
  });

  final XItem item;
  final bool favourite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return TvFocus(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7.5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            NetImage(item.icon, fit: BoxFit.cover, cacheWidth: 220, fallback: Icons.movie_rounded),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(7, 22, 7, 6),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xE6000000)],
                  ),
                ),
                child: Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (favourite)
              const Positioned(top: 5, right: 5, child: Icon(Icons.star_rounded, color: C.accent, size: 16)),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askSearch(BuildContext context, String initial) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.panel,
      title: const Text('Search'),
      content: SizedBox(
        width: 380,
        child: TvField(
          controller: controller,
          label: 'Name',
          icon: Icons.search_rounded,
          autofocus: true,
          action: TextInputAction.search,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(controller.text.trim()), child: const Text('Search')),
      ],
    ),
  );
}
