import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

bool _isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;

/// A card that can be reached with the remote (D-pad) and shows a clear
/// highlight while focused. OK opens it; holding OK (or the Menu button,
/// or a long press on a touch screen) calls [onLongPress].
class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.onFocus,
    this.autofocus = false,
    this.focusNode,
    this.radius = 10,
    this.color = C.card,
    this.selected = false,
    this.focusBorder = C.accent,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onFocus;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final Color color;
  final bool selected;
  final Color focusBorder;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false;
  bool _down = false;
  bool _longFired = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.onLongPress == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.contextMenu) {
      if (event is KeyDownEvent) widget.onLongPress!();
      return KeyEventResult.handled;
    }
    if (!_isSelectKey(key)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _down = true;
      _longFired = false;
    } else if (event is KeyRepeatEvent) {
      if (_down && !_longFired) {
        _longFired = true;
        widget.onLongPress!();
      }
    } else if (event is KeyUpEvent) {
      final tap = _down && !_longFired;
      _down = false;
      _longFired = false;
      if (tap) widget.onTap();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.radius);
    final Color fill = _focused
        ? Color.alphaBlend(C.accent.withOpacity(0.20), widget.color)
        : (widget.selected ? Color.alphaBlend(C.accent.withOpacity(0.08), widget.color) : widget.color);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: radius,
          focusColor: Colors.transparent,
          hoverColor: Colors.transparent,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onFocusChange: (value) {
            if (_focused != value) setState(() => _focused = value);
            if (!value) {
              _down = false;
              _longFired = false;
            }
            if (value) widget.onFocus?.call();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: radius,
              border: Border.all(
                color: _focused ? widget.focusBorder : (widget.selected ? C.accent.withOpacity(0.45) : Colors.transparent),
                width: 2.5,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Text field that lets the remote leave it with Up / Down.
class TvField extends StatelessWidget {
  const TvField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.focusNode,
    this.obscure = false,
    this.autofocus = false,
    this.action = TextInputAction.next,
    this.keyboardType,
    this.onSubmitted,
    this.onUp,
    this.onDown,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FocusNode? focusNode;
  final bool obscure;
  final bool autofocus;
  final TextInputAction action;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: color, width: 2.5),
        );
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          if (onDown != null) {
            onDown!();
          } else {
            FocusScope.of(context).nextFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowUp): () {
          if (onUp != null) {
            onUp!();
          } else {
            FocusScope.of(context).previousFocus();
          }
        },
      },
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: keyboardType,
        textInputAction: action,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 16, color: C.text),
        cursorColor: C.accent,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: C.dim),
          floatingLabelStyle: const TextStyle(color: C.accent),
          prefixIcon: Icon(icon, color: C.dim, size: 20),
          filled: true,
          fillColor: C.card,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: border(Colors.transparent),
          focusedBorder: border(C.accent),
        ),
      ),
    );
  }
}

/// Network picture with a quiet placeholder when it is missing or broken.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.contain, this.cacheWidth = 160, this.fallback = Icons.tv});

  final String url;
  final BoxFit fit;
  final int cacheWidth;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final placeholder = Center(child: Icon(fallback, color: C.dim.withOpacity(0.5), size: 22));
    if (!url.startsWith('http')) return placeholder;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => placeholder,
      frameBuilder: (_, child, frame, sync) => frame == null && !sync ? placeholder : child,
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(strokeWidth: 3, color: C.accent),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: const TextStyle(color: C.dim, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

/// Message with a "Try again" button, used when a list cannot be loaded.
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.message, required this.onRetry, this.autofocus = false});
  final String message;
  final VoidCallback onRetry;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: C.dim, size: 34),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center, style: const TextStyle(color: C.text, fontSize: 15)),
          ),
          const SizedBox(height: 16),
          TvFocus(
            autofocus: autofocus,
            onTap: onRetry,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Text('Try again', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
