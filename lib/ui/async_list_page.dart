import 'package:flutter/material.dart';

import '../data/app_state.dart';
import 'expressive.dart';

/// Page à grand titre qui charge une liste à la demande, avec tirer-pour-rafraîchir.
class AsyncListPage<T> extends StatefulWidget {
  const AsyncListPage({
    super.key,
    required this.title,
    required this.load,
    required this.itemBuilder,
    required this.empty,
  });

  final String title;
  final Future<List<T>> Function() load;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget empty;

  @override
  State<AsyncListPage<T>> createState() => _AsyncListPageState<T>();
}

class _AsyncListPageState<T> extends State<AsyncListPage<T>> {
  late Future<List<T>> _future = widget.load();

  Future<void> _refresh() async {
    final future = widget.load();
    setState(() {
      _future = future;
    });
    await future.catchError((_) => <T>[]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: 80,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: PageHeader(title: widget.title)),
            FutureBuilder<List<T>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const SliverFillRemaining(child: Center(child: ExpressiveLoader()));
                }
                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Chargement impossible',
                      message: AppState.errorMessage(snapshot.error!),
                      action: FilledButton.tonal(onPressed: _refresh, child: const Text('Réessayer')),
                    ),
                  );
                }
                final items = snapshot.data!;
                if (items.isEmpty) return SliverFillRemaining(hasScrollBody: false, child: widget.empty);
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) =>
                        EnterAnimation(index: i, child: widget.itemBuilder(context, items[i], i)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
