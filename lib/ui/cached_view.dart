import 'dart:async';

import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'expressive.dart';

/// État d'un chargement avec cache, donné au [CachedView.builder].
class CacheStatus {
  const CacheStatus({required this.refreshing, required this.error, required this.refresh});

  /// Une version à jour est en cours de téléchargement.
  final bool refreshing;

  /// Le dernier téléchargement a échoué : les données affichées sont la version enregistrée.
  final Object? error;

  /// Relance le téléchargement ; se termine quand la version à jour est arrivée (ou a échoué).
  final Future<void> Function() refresh;
}

/// Affiche tout de suite la version enregistrée, puis la remplace par la version à jour
/// dès qu'elle arrive. Le chargement plein écran n'apparaît que si rien n'est enregistré.
class CachedView<T> extends StatefulWidget {
  const CachedView({
    super.key,
    required this.load,
    required this.builder,
    this.loading,
    this.failed,
    this.reloadKey,
  });

  /// Change cette valeur pour relancer le chargement (par exemple un autre dossier).
  final Object? reloadKey;

  final Stream<T> Function() load;
  final Widget Function(BuildContext context, T data, CacheStatus status) builder;

  /// Rien d'enregistré, téléchargement en cours. Par défaut : un indicateur centré.
  final Widget Function(BuildContext context)? loading;

  /// Rien d'enregistré et le téléchargement a échoué. Par défaut : un état vide avec "Réessayer".
  final Widget Function(BuildContext context, Object error, Future<void> Function() retry)? failed;

  @override
  State<CachedView<T>> createState() => _CachedViewState<T>();
}

class _CachedViewState<T> extends State<CachedView<T>> {
  StreamSubscription<T>? _sub;
  T? _data;
  bool _hasData = false;
  bool _refreshing = false;
  Object? _error;
  Completer<void>? _done;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CachedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadKey != oldWidget.reloadKey) _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() {
    _sub?.cancel();
    final previous = _done;
    if (previous != null && !previous.isCompleted) previous.complete();
    final done = _done = Completer<void>();
    void finish() {
      if (!done.isCompleted) done.complete();
    }

    if (mounted && (_error != null || !_refreshing)) {
      setState(() {
        _refreshing = true;
        _error = null;
      });
    } else {
      _refreshing = true;
      _error = null;
    }
    _sub = widget.load().listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _data = value;
          _hasData = true;
        });
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _error = e;
            _refreshing = false;
          });
        }
        finish();
      },
      onDone: () {
        if (mounted) setState(() => _refreshing = false);
        finish();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  @override
  Widget build(BuildContext context) {
    if (_hasData) {
      return widget.builder(
        context,
        _data as T,
        CacheStatus(refreshing: _refreshing, error: _error, refresh: _refresh),
      );
    }
    if (_error != null) {
      return widget.failed?.call(context, _error!, _refresh) ??
          EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Chargement impossible',
            message: AppState.errorMessage(_error!),
            action: FilledButton.tonal(onPressed: _refresh, child: const Text('Réessayer')),
          );
    }
    return widget.loading?.call(context) ?? const Center(child: ExpressiveLoader());
  }
}

/// Petit bandeau "à jour / mise à jour / hors ligne", à placer sous un titre de page.
class CacheBanner extends StatelessWidget {
  const CacheBanner({super.key, required this.status});

  final CacheStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Widget child;
    if (status.error != null) {
      child = Padding(
        key: const ValueKey('offline'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hors ligne : dernière version enregistrée.',
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ),
      );
    } else if (status.refreshing) {
      child = const Padding(
        key: ValueKey('refreshing'),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: LinearProgressIndicator(minHeight: 3, borderRadius: BorderRadius.all(Radius.circular(2))),
      );
    } else {
      child = const SizedBox(key: ValueKey('idle'), width: double.infinity);
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}
