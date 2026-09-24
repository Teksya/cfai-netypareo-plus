/// Un cours de l'emploi du temps.
class Seance {
  const Seance({
    required this.uid,
    required this.codeSeance,
    required this.subject,
    required this.teachers,
    required this.room,
    required this.group,
    required this.start,
    required this.end,
  });

  final String uid;

  /// Code NetYParéo de la séance, utile pour ouvrir son détail. Null si inconnu.
  final int? codeSeance;
  final String subject;
  final String teachers;
  final String room;
  final String group;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'codeSeance': codeSeance,
        'subject': subject,
        'teachers': teachers,
        'room': room,
        'group': group,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
      };

  factory Seance.fromJson(Map<String, dynamic> json) => Seance(
        uid: json['uid'] as String,
        codeSeance: json['codeSeance'] as int?,
        subject: json['subject'] as String,
        teachers: json['teachers'] as String,
        room: json['room'] as String,
        group: json['group'] as String,
        start: DateTime.parse(json['start'] as String),
        end: DateTime.parse(json['end'] as String),
      );
}

/// Détail d'une séance (modale NetYParéo).
class SeanceDetail {
  const SeanceDetail({
    required this.title,
    required this.infos,
    required this.cahiers,
  });

  final String title;

  /// Groupe(s), Formateur(s), Salle(s)... dans l'ordre du site. Les valeurs "-" sont retirées.
  final Map<String, String> infos;
  final List<CahierEntry> cahiers;
}

/// Une entrée du cahier de textes.
class CahierEntry {
  const CahierEntry({
    required this.title,
    required this.content,
    this.subject = '',
    this.when = '',
    this.teacher = '',
    this.codeSeance,
    this.date,
    this.resources = const [],
  });

  final String title;
  final String content;
  final String subject;
  final String when;

  /// Début de la séance, si connu.
  final DateTime? date;
  final String teacher;
  final int? codeSeance;
  final List<DocumentLink> resources;
}

class DocumentLink {
  const DocumentLink(this.name, this.path);
  final String name;

  /// Chemin relatif à l'hôte, ex. /netypareo/index.php/document/telecharger/xxx/
  final String path;
}

class Absence {
  const Absence({
    required this.from,
    required this.to,
    required this.duration,
    required this.reason,
    required this.detail,
  });

  final String from;
  final String to;
  final String duration;
  final String reason;
  final String detail;
}

/// Identité et identifiants lus après la connexion.
class Profile {
  const Profile({
    required this.displayName,
    required this.period,
    required this.codeApprenant,
    required this.codeInscription,
    required this.formation,
  });

  final String displayName;
  final String period;
  final int codeApprenant;
  final int? codeInscription;
  final String formation;

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'period': period,
        'codeApprenant': codeApprenant,
        'codeInscription': codeInscription,
        'formation': formation,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        displayName: json['displayName'] as String,
        period: json['period'] as String,
        codeApprenant: json['codeApprenant'] as int,
        codeInscription: json['codeInscription'] as int?,
        formation: json['formation'] as String,
      );
}

/// Un travail à faire donné pendant un cours.
class TravailAFaire {
  const TravailAFaire({
    required this.code,
    required this.subject,
    required this.dueDate,
    required this.content,
    this.codeMatiere,
    this.givenOn = '',
    this.codeSeance,
    this.teacher = '',
    this.documents = const [],
    this.late = false,
    this.done = false,
    this.codeTravailFait,
    this.toHandIn = false,
  });

  final int code;
  final String subject;
  final int? codeMatiere;

  /// Jour pour lequel le travail est à faire.
  final DateTime dueDate;

  /// Date du cours pendant lequel il a été donné, telle qu'affichée par le site.
  final String givenOn;
  final int? codeSeance;
  final String teacher;
  final String content;
  final List<DocumentLink> documents;

  /// Rangé par le site dans la partie "en retard".
  final bool late;

  /// Déclaré comme fait ; [codeTravailFait] sert alors à annuler.
  final bool done;
  final int? codeTravailFait;

  /// Le formateur attend un rendu (fichier) : ça se fait sur le site.
  final bool toHandIn;
}
