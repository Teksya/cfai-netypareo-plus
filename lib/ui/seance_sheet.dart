import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../data/app_state.dart';
import '../data/models.dart';
import '../main.dart';
import 'expressive.dart';
import 'format.dart';
import 'theme.dart';

Future<void> showSeanceSheet(BuildContext context, Seance seance) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) => _SeanceSheet(seance: seance, controller: controller),
    ),
  );
}

class _SeanceSheet extends StatefulWidget {
  const _SeanceSheet({required this.seance, required this.controller});

  final Seance seance;
  final ScrollController controller;

  @override
  State<_SeanceSheet> createState() => _SeanceSheetState();
}

class _SeanceSheetState extends State<_SeanceSheet> {
  Future<SeanceDetail>? _detail;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = widget.seance.codeSeance;
    if (_detail == null && code != null) _detail = AppScope.read(context).seanceDetail(code);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.seance;
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final colors = subjectColors(s.subject, theme.brightness);
    final hm = DateFormat.Hm();

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: ShapeDecoration(color: colors.container, shape: const CookieBorder(lobes: 7, depth: 0.08)),
              child: Icon(Icons.class_rounded, color: colors.onContainer),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(capitalizeWords(s.subject), style: text.headlineSmall)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.schedule_rounded, size: 18),
              label: Text('${hm.format(s.start)} - ${hm.format(s.end)}'),
            ),
            Chip(
              avatar: const Icon(Icons.event_rounded, size: 18),
              label: Text(DateFormat.MMMMEEEEd().format(s.start)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_detail == null)
          _BasicInfos(seance: s)
        else
          FutureBuilder<SeanceDetail>(
            future: _detail,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(32), child: Center(child: ExpressiveLoader()));
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _BasicInfos(seance: s),
                    const SizedBox(height: 12),
                    Text(
                      'Détail indisponible : ${AppState.errorMessage(snapshot.error!)}',
                      style: text.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ],
                );
              }
              return _DetailView(detail: snapshot.data!);
            },
          ),
      ],
    );
  }
}

class _BasicInfos extends StatelessWidget {
  const _BasicInfos({required this.seance});

  final Seance seance;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(entries: {
      if (seance.teachers.isNotEmpty) 'Formateur(s)': seance.teachers,
      if (seance.room.isNotEmpty) 'Salle(s)': seance.room,
      if (seance.group.isNotEmpty) 'Groupe(s)': seance.group,
    });
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView({required this.detail});

  final SeanceDetail detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(entries: detail.infos),
        const SizedBox(height: 24),
        Text('Cahier de textes', style: text.titleLarge),
        const SizedBox(height: 12),
        if (detail.cahiers.isEmpty)
          Text('Rien de saisi pour cette séance.', style: text.bodyMedium)
        else
          for (final cahier in detail.cahiers) ...[CahierCard(entry: cahier), const SizedBox(height: 12)],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.entries});

  final Map<String, String> entries;

  static const _icons = {
    'Groupe(s)': Icons.groups_rounded,
    'Formateur(s)': Icons.person_rounded,
    'Salle(s)': Icons.room_rounded,
    'Matériel(s)': Icons.build_rounded,
    'Visioconférence': Icons.videocam_rounded,
    'Commentaire': Icons.comment_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (final e in entries.entries)
              ListTile(
                leading: Icon(_icons[e.key] ?? Icons.info_rounded, color: scheme.primary),
                title: Text(e.key, style: text.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                subtitle: Text(e.value, style: text.bodyLarge),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pièce jointe : un appui la télécharge (avec la session) puis l'ouvre dans l'app adaptée du téléphone.
class AttachmentChip extends StatefulWidget {
  const AttachmentChip({super.key, required this.link});

  final DocumentLink link;

  @override
  State<AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends State<AttachmentChip> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final download = await AppScope.read(context).downloadDocument(widget.link);
      final result = await OpenFilex.open(download.file.path, type: download.mimeType);
      if (result.type == ResultType.noAppToOpen) {
        messenger.showSnackBar(SnackBar(
          content: Text('Aucune application pour ouvrir ce type de fichier (${widget.link.name.split('.').last}).'),
        ));
      } else if (result.type != ResultType.done) {
        messenger.showSnackBar(SnackBar(content: Text('Ouverture impossible : ${result.message}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(AppState.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static IconData _icon(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' => Icons.image_rounded,
      'doc' || 'docx' || 'odt' || 'txt' => Icons.description_rounded,
      'xls' || 'xlsx' || 'ods' || 'csv' => Icons.table_chart_rounded,
      'ppt' || 'pptx' || 'odp' => Icons.slideshow_rounded,
      'zip' || 'rar' || '7z' => Icons.folder_zip_rounded,
      _ => Icons.attach_file_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SpringPress(
      child: ActionChip(
        avatar: _busy
            ? const SizedBox.square(dimension: 18, child: ExpressiveLoader(size: 18))
            : Icon(_icon(widget.link.name), size: 18),
        label: Text(widget.link.name, overflow: TextOverflow.ellipsis),
        tooltip: 'Ouvrir ${widget.link.name}',
        onPressed: _open,
      ),
    );
  }
}

/// Carte d'une entrée de cahier de textes (réutilisée par l'onglet Cahier).
class CahierCard extends StatelessWidget {
  const CahierCard({super.key, required this.entry, this.showSubject = false});

  final CahierEntry entry;
  final bool showSubject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final colors = subjectColors(entry.subject, theme.brightness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSubject && entry.subject.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: colors.container, borderRadius: BorderRadius.circular(99)),
                child: Text(capitalizeWords(entry.subject), style: text.labelMedium?.copyWith(color: colors.onContainer)),
              ),
            if (entry.title.isNotEmpty) Text(entry.title, style: text.titleMedium),
            if (entry.when.isNotEmpty || entry.teacher.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [entry.when, entry.teacher].where((s) => s.isNotEmpty).join(' · '),
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            // Pièces jointes avant le texte, souvent long : on les trouve sans défiler.
            if (entry.resources.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in entry.resources) AttachmentChip(link: r),
                ],
              ),
            ],
            if (entry.content.isNotEmpty && entry.content != entry.title) ...[
              const SizedBox(height: 12),
              SelectableText(entry.content, style: text.bodyMedium?.copyWith(height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}
