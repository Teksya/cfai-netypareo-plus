import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../main.dart';
import 'cached_view.dart';
import 'expressive.dart';
import 'seance_sheet.dart';

/// Page secondaire (ouverte depuis l'onglet "Plus") : grand titre repliable et bouton retour,
/// contenu enregistré affiché tout de suite puis mis à jour.
class _CachedListPage<T> extends StatelessWidget {
  const _CachedListPage({
    required this.title,
    required this.load,
    required this.empty,
    required this.itemBuilder,
    this.subtitle,
  });

  final String title;
  final String? Function(List<T> items)? subtitle;
  final Stream<List<T>> Function() load;
  final Widget empty;
  final Widget Function(BuildContext context, T item) itemBuilder;

  Widget _page(List<Widget> slivers, {String? subtitle, Future<void> Function()? onRefresh}) {
    final view = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverAppBar(pinned: true),
        SliverToBoxAdapter(
          child: Builder(
            builder: (context) {
              final text = Theme.of(context).textTheme;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.headlineLarge),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: text.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        ...slivers,
      ],
    );
    return onRefresh == null ? view : RefreshIndicator(onRefresh: onRefresh, edgeOffset: 80, child: view);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CachedView<List<T>>(
        load: load,
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
        builder: (context, items, status) => _page(
          subtitle: subtitle?.call(items),
          onRefresh: status.refresh,
          [
            SliverToBoxAdapter(child: CacheBanner(status: status)),
            if (items.isEmpty)
              SliverFillRemaining(hasScrollBody: false, child: empty)
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => EnterAnimation(index: i, child: itemBuilder(context, items[i])),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Documents (espace documentaire de l'apprenant)

/// Un dossier de l'espace Documents ; [folder] null pour la racine.
class DocumentsPage extends StatelessWidget {
  const DocumentsPage({super.key, this.folder});

  final DocEntry? folder;

  @override
  Widget build(BuildContext context) {
    return _CachedListPage<DocEntry>(
      title: folder?.name ?? 'Documents',
      load: () => AppScope.read(context).documents(folder),
      subtitle: (items) {
        final files = items.where((e) => !e.isFolder).length;
        final folders = items.length - files;
        return [
          if (folders > 0) '$folders dossier${folders > 1 ? 's' : ''}',
          if (files > 0) '$files fichier${files > 1 ? 's' : ''}',
        ].join(' · ');
      },
      empty: const EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Dossier vide',
        message: 'Aucun document déposé ici pour le moment.',
      ),
      itemBuilder: (context, entry) => entry.isFolder ? _FolderTile(entry: entry) : _FileTile(entry: entry),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.entry});

  final DocEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.secondaryContainer,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: ShapeDecoration(color: scheme.secondary, shape: const CookieBorder(lobes: 6, depth: 0.08)),
          child: Icon(Icons.folder_rounded, color: scheme.onSecondary),
        ),
        title: Text(entry.name, style: TextStyle(color: scheme.onSecondaryContainer)),
        subtitle: entry.count == null
            ? null
            : Text(
                entry.count == 0 ? 'Vide' : '${entry.count} fichier${entry.count! > 1 ? 's' : ''}',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
        trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSecondaryContainer),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DocumentsPage(folder: entry),
        )),
      ),
    );
  }
}

class _FileTile extends StatefulWidget {
  const _FileTile({required this.entry});

  final DocEntry entry;

  @override
  State<_FileTile> createState() => _FileTileState();
}

class _FileTileState extends State<_FileTile> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy || widget.entry.download == null) return;
    setState(() => _busy = true);
    await openDocument(context, widget.entry.download!);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final scheme = Theme.of(context).colorScheme;
    final details = [
      if (e.type.isNotEmpty) e.type,
      if (e.modified.isNotEmpty) e.modified,
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: ShapeDecoration(color: scheme.tertiaryContainer, shape: const CookieBorder(lobes: 6, depth: 0.08)),
          child: _busy
              ? const Center(child: ExpressiveLoader(size: 22))
              : Icon(documentIcon(e.name), color: scheme.onTertiaryContainer),
        ),
        title: Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: details.isEmpty ? null : Text(details),
        trailing: const Icon(Icons.open_in_new_rounded),
        onTap: _open,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Documents de liaison

class DocsLiaisonPage extends StatelessWidget {
  const DocsLiaisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _CachedListPage<DocLiaison>(
      title: 'Documents de liaison',
      load: AppScope.read(context).docsLiaison,
      subtitle: (items) {
        final pending = items.where((d) => d.toReturn && !d.returned).length;
        return pending == 0 ? null : '$pending à retourner';
      },
      empty: const EmptyState(
        icon: Icons.swap_horiz_rounded,
        title: 'Aucun document de liaison',
        message: 'Rien reçu du CFA ou de ton entreprise sur les 12 derniers mois.',
      ),
      itemBuilder: (context, doc) => _LiaisonTile(doc: doc),
    );
  }
}

class _LiaisonTile extends StatelessWidget {
  const _LiaisonTile({required this.doc});

  final DocLiaison doc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final date = DateFormat('d MMM yyyy');
    final pending = doc.toReturn && !doc.returned;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: ShapeDecoration(
            color: pending ? scheme.errorContainer : scheme.primaryContainer,
            shape: const CookieBorder(lobes: 6, depth: 0.08),
          ),
          child: Icon(
            pending ? Icons.assignment_return_rounded : (doc.read ? Icons.drafts_rounded : Icons.mail_rounded),
            color: pending ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          doc.name.isEmpty ? 'Document' : doc.name,
          style: doc.read ? null : const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([
              if (doc.sender.isNotEmpty) doc.sender,
              if (doc.created != null) date.format(doc.created!),
            ].join(' · ')),
            if (pending)
              Text(
                doc.due == null ? 'À retourner' : 'À retourner avant le ${date.format(doc.due!)}',
                style: text.bodySmall?.copyWith(color: scheme.error),
              )
            else if (doc.returned)
              Text('Retourné', style: text.bodySmall?.copyWith(color: scheme.primary)),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showLiaisonSheet(context, doc),
      ),
    );
  }
}

Future<void> _showLiaisonSheet(BuildContext context, DocLiaison doc) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) {
        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(doc.name.isEmpty ? 'Document' : doc.name, style: text.headlineSmall),
            if (doc.sender.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('De ${doc.sender}', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            CachedView<({String text, List<DocumentLink> documents})>(
              load: () => AppScope.read(context).docLiaisonDetail(doc.code),
              loading: (context) => const Padding(padding: EdgeInsets.all(32), child: Center(child: ExpressiveLoader())),
              failed: (context, error, retry) => Text(
                'Détail indisponible : ${AppState.errorMessage(error)}',
                style: text.bodySmall?.copyWith(color: scheme.error),
              ),
              builder: (context, detail, status) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (detail.text.isNotEmpty) SelectableText(detail.text, style: text.bodyLarge?.copyWith(height: 1.4)),
                  if (detail.documents.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [for (final d in detail.documents) AttachmentChip(link: d)],
                    ),
                  ],
                  if (doc.toReturn && !doc.returned) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Ce document est à retourner : fais-le depuis le site NetYParéo.',
                      style: text.bodySmall?.copyWith(color: scheme.tertiary),
                    ),
                  ],
                  if (status.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Hors ligne : dernière version enregistrée.',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
