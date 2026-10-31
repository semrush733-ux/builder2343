import 'package:flutter/material.dart';

import '../i18n.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';

/// "Who is watching?": one tile per profile. Each profile keeps its own favourites,
/// recently watched, resume points and parental PIN.
class ProfilePickerScreen extends StatefulWidget {
  const ProfilePickerScreen({super.key, required this.next});

  /// Builds the screen to open once a profile is chosen (the home screen).
  final WidgetBuilder next;

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen> {
  void _pick(String id) {
    Store.setProfile(id);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: widget.next));
  }

  Future<void> _add() async {
    final name = await askProfileName(context);
    if (name == null || !mounted) return;
    Store.addProfile(name.text, kids: name.kids);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final list = Store.profiles;
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: Aurora(strength: 1.0)),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                const Logo(),
                const SizedBox(height: 22),
                Text(t('Who is watching?'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < list.length; i++)
                            _Avatar(
                              name: '${list[i]['name']}',
                              kids: list[i]['kids'] == true,
                              index: i,
                              autofocus: list[i]['id'] == Store.profileId,
                              onTap: () => _pick('${list[i]['id']}'),
                            ),
                          _Avatar(name: t('Add profile'), kids: false, index: -1, add: true, onTap: _add),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.kids, required this.index, required this.onTap, this.add = false, this.autofocus = false});
  final String name;
  final bool kids;
  final int index;
  final bool add;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = [Ui.c1, Ui.c2, Ui.c3];
    final c = index < 0 ? C.dim : colors[index % 3];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: TvFocus(
        autofocus: autofocus,
        radius: 24,
        color: const Color(0x80161934),
        onTap: onTap,
        child: SizedBox(
          width: 150,
          height: 190,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: add ? null : LinearGradient(colors: [c, c.withValues(alpha: 0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: add ? Border.all(color: C.dim, width: 2) : null,
                ),
                child: add
                    ? const Icon(Icons.add_rounded, size: 40, color: C.dim)
                    : Center(
                        child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.black87)),
                      ),
              ),
              const SizedBox(height: 14),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              if (kids) const Text('KIDS', style: TextStyle(fontSize: 11, color: C.dim, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

class NewProfile {
  const NewProfile(this.text, this.kids);
  final String text;
  final bool kids;
}

/// Asks for a profile name (and whether it is a kids profile). Null when cancelled.
Future<NewProfile?> askProfileName(BuildContext context, {String initial = ''}) {
  final c = TextEditingController(text: initial);
  var kids = false;
  return showDialog<NewProfile>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: C.panel,
        title: Text(t('Add profile')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c, autofocus: true, decoration: InputDecoration(hintText: t('Name'))),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: kids,
              onChanged: (v) => setS(() => kids = v ?? false),
              title: const Text('Kids profile (hides adult content)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel'))),
          FilledButton(
            onPressed: () {
              final n = c.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, NewProfile(n, kids));
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}
