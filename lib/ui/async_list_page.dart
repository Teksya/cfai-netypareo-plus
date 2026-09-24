import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'cached_view.dart';
import 'expressive.dart';

/// Page à grand titre : liste enregistrée affichée tout de suite, mise à jour derrière,
/// tirer-pour-rafraîchir.
class AsyncListPage<T> extends StatefulWidget {
  const AsyncListPage({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    required this.empty,
  });

  final String title;
  final Stream<List<T>> Function() load;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget empty;

  @override
  State<AsyncListPage<T>> createState() => _AsyncListPageState<T>();
}

class _AsyncListPageState<T> extends State<AsyncListPage<T>> {
  Widget _page(List<Widget> slivers, {Future<void> Function()? onRefresh}) {
    final view = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [SliverToBoxAdapter(child: PageHeader(title: widget.title)), ...slivers],
    );
    return onRefresh == null ? view : RefreshIndicator(onRefresh: onRefresh, edgeOffset: 80, child: view);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CachedView<List<T>>(
        load: widget.load,
        loading: (context) => _page(const [SliverFillRemaining(child: Center(child: ExpressiveLoader()))]),
        failed: (context, error, retry) => _page(onRefresh: retry, [
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Chargement impossible',
              message: AppState.errorMessage(error),
              action: FilledButton.tonal(onPressed: retry, child: const Text('Réessayer')),
            ),
          ),
        ]),
        builder: (context, items, status) => _page(onRefresh: status.refresh, [
          SliverToBoxAdapter(child: CacheBanner(status: status)),
          if (items.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: widget.empty)
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) => EnterAnimation(index: i, child: widget.itemBuilder(context, items[i], i)),
              ),
            ),
        ]),
      ),
    );
  }
}
