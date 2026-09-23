import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Forme "cookie" de Material 3 Expressive : un cercle aux bords ondulés.
class CookieBorder extends OutlinedBorder {
  const CookieBorder({this.lobes = 9, this.depth = 0.08, this.rotation = 0, super.side});

  final int lobes;

  /// Profondeur des ondulations, en fraction du rayon.
  final double depth;
  final double rotation;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => getOuterPath(rect.deflate(side.width));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final center = rect.center;
    final radius = rect.shortestSide / 2;
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final r = radius * (1 - depth + depth * math.cos(lobes * (t + rotation)));
      final point = center + Offset(math.cos(t), math.sin(t)) * r;
      i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(getOuterPath(rect), side.toPaint());
  }

  @override
  CookieBorder copyWith({BorderSide? side}) =>
      CookieBorder(lobes: lobes, depth: depth, rotation: rotation, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => CookieBorder(lobes: lobes, depth: depth, rotation: rotation, side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is CookieBorder) {
      return CookieBorder(
        lobes: lobes,
        depth: a.depth + (depth - a.depth) * t,
        rotation: a.rotation + (rotation - a.rotation) * t,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is CookieBorder) return b.lerpFrom(this, t);
    return super.lerpTo(b, t);
  }
}

/// Ressort "expressif" : rapide et légèrement rebondissant.
const SpringDescription kExpressiveSpring = SpringDescription(mass: 1, stiffness: 380, damping: 18);

/// Réduit légèrement son enfant à l'appui, puis le relâche avec un ressort.
class SpringPress extends StatefulWidget {
  const SpringPress({super.key, required this.child, this.onTap, this.onLongPress, this.pressedScale = 0.95});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  State<SpringPress> createState() => _SpringPressState();
}

class _SpringPressState extends State<SpringPress> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(vsync: this, value: 1);

  void _animateTo(double target) {
    _controller.animateWith(SpringSimulation(kExpressiveSpring, _controller.value, target, _controller.velocity));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listener (et non GestureDetector) pour réagir même quand l'enfant gère lui-même le tap.
    Widget child = Listener(
      onPointerDown: (_) => _animateTo(widget.pressedScale),
      onPointerUp: (_) => _animateTo(1),
      onPointerCancel: (_) => _animateTo(1),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Transform.scale(scale: _controller.value, child: child),
        child: widget.child,
      ),
    );
    if (widget.onTap != null || widget.onLongPress != null) {
      child = GestureDetector(onTap: widget.onTap, onLongPress: widget.onLongPress, child: child);
    }
    return child;
  }
}

/// Indicateur de chargement M3 Expressive : une forme qui tourne et ondule.
class ExpressiveLoader extends StatefulWidget {
  const ExpressiveLoader({super.key, this.size = 48, this.color});

  final double size;
  final Color? color;

  @override
  State<ExpressiveLoader> createState() => _ExpressiveLoaderState();
}

class _ExpressiveLoaderState extends State<ExpressiveLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'Chargement',
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final wave = (math.sin(t * 2 * math.pi) + 1) / 2;
          return Transform.rotate(
            angle: t * 2 * math.pi,
            child: SizedBox.square(
              dimension: widget.size,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: color,
                  shape: CookieBorder(lobes: wave > 0.5 ? 7 : 5, depth: 0.04 + 0.1 * wave),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Apparition en glissant et en fondu, décalée selon [index] (listes).
class EnterAnimation extends StatelessWidget {
  const EnterAnimation({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + 50 * index.clamp(0, 8)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 24 * (1 - value)), child: child),
      ),
      child: child,
    );
  }
}

/// Grand titre de page, aligné à gauche (même style que l'onglet Planning).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 12, 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.headlineLarge),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// Message plein écran (vide, erreur) avec une forme cookie.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: ShapeDecoration(color: scheme.tertiaryContainer, shape: const CookieBorder(lobes: 12, depth: 0.06)),
              child: Icon(icon, size: 48, color: scheme.onTertiaryContainer),
            ),
            const SizedBox(height: 24),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}
