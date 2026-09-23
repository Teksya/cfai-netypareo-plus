# 📱 NetYParéo+ (cfai-netypareo-plus)

Bienvenue sur le dépôt de **NetYParéo+**, une application Flutter pour consulter NetYParéo, le portail des apprentis du CFAI LDA de Saint-Étienne, sans passer par le site.

> 🐒 L'idée vient de [Papillon](https://github.com/PapillonApp), l'application qui remplace celles de Pronote et d'École Directe. Ici, c'est la même démarche pour NetYParéo : un portail lent, pensé pour un écran d'ordinateur, devient une application mobile rapide.

| Où ? | Quoi ? |
| --- | --- |
| [Ce dépôt](https://github.com/Teksya/cfai-netypareo-plus) | Le code de l'application Flutter |
| [docs/netypareo-api.md](docs/netypareo-api.md) | La carte des endpoints de NetYParéo, relevés sur l'instance du CFA |
| [netypareo.citedesentreprises.org](https://netypareo.citedesentreprises.org/netypareo/) | Le portail officiel, que l'application interroge |

### 📚 Concept du projet

NetYParéo contient tout ce dont un apprenti a besoin : l'emploi du temps, le calendrier centre / entreprise, les notes, les absences, le cahier de textes, le travail à faire et les documents. Le site est lent sur téléphone, la session expire vite, et il ne prévient de rien. **NetYParéo+** reprend ces données dans une application pensée pour le téléphone, avec une synchronisation en arrière-plan et des notifications.

### 🚀 Fonctionnalités prévues

- **Emploi du temps** par jour et par semaine, consultable hors ligne, avec le détail de chaque séance (salle, formateur, contenu du cahier de textes).
- **Calendrier de formation** : les semaines au centre et les semaines en entreprise.
- **Notes et bulletin**, **absences**.
- **Cahier de textes** et **travail à faire**.
- **Documents** : consultation et téléchargement.
- **Notifications** quand un cours est déplacé, ajouté ou annulé.

### 🔍 Jusqu'où va le projet

- Le projet en est à la **cartographie** : les endpoints sont relevés dans [docs/netypareo-api.md](docs/netypareo-api.md), le code de l'application n'est pas encore écrit.
- NetYParéo n'a **pas d'API officielle**. L'application lit les mêmes pages et les mêmes appels que le site : si YMAG (l'éditeur) change le site, une partie de l'application peut cesser de fonctionner jusqu'à sa mise à jour.
- Les notes n'ont pas encore été testées : aucune note n'était saisie au moment de l'exploration (septembre 2026).
- L'application ne fait que **lire**. Rendre un devoir ou déposer un document restent à faire sur le site.

## 🛠️ Comment ça marche

Le détail est dans [docs/netypareo-api.md](docs/netypareo-api.md). En résumé :

1. **Connexion** : `POST /authentication/` avec l'identifiant, le mot de passe et le jeton CSRF de la page de connexion. La session est ensuite gardée dans un cookie.
2. **Emploi du temps** : le flux iCalendar personnel de l'apprenant. Il fonctionne sans session, ce qui permet la synchronisation en arrière-plan.
3. **Le reste** : du JSON quand le site en fournit (planning, jours de cours, calendrier), sinon la lecture des pages HTML. Les pages sont encodées en `windows-1252`, le JSON en UTF-8.
4. **Maintien de la session** : `GET /rester-connecter/`, appelé tant que l'application est ouverte.

## 🚀 Lancer l'application en local

> 🚧 Le code de l'application n'est pas encore dans le dépôt. Cette section sera complétée à son arrivée.

Il te faudra [Flutter](https://docs.flutter.dev/get-started/install) (canal stable).

```bash
git clone https://github.com/Teksya/cfai-netypareo-plus.git
cd cfai-netypareo-plus
flutter pub get
flutter run
```

| Commande | Effet |
| --- | --- |
| `flutter pub get` | Installe les dépendances (à faire une fois, après le clone) |
| `flutter run` | Lance l'application sur un téléphone ou un émulateur |
| `flutter test` | Lance les tests |
| `flutter build apk` | Construit l'application Android |

Paquets prévus : `dio` et `cookie_jar` (requêtes et session), `html` (lecture des pages), `flutter_secure_storage` (identifiants).

## 📝 Contribution

1. **Forke** le dépôt (bouton "Fork" en haut à droite).

> Un **fork** est une copie du dépôt sur ton propre compte GitHub. Tu peux y travailler sans risque : l'original n'est pas touché. Quand ta modification est prête, tu demandes à l'intégrer au projet principal avec une pull request.

2. **Clone** ton fork sur ta machine :
    ```bash
    git clone https://github.com/<ton-pseudo>/cfai-netypareo-plus.git
    ```
3. **Crée** une nouvelle branche pour ta modification :
    ```bash
    git checkout -b <branche>
    ```
4. **Fais** ta modification, vérifie que les tests passent, puis **commite** :
    ```bash
    flutter test
    git add .
    git commit -m "Décris ta modification en une phrase"
    ```
5. **Pousse** vers ton fork :
    ```bash
    git push -u origin <branche>
    ```
6. **Ouvre** une pull request vers le dépôt principal.

Un endpoint a changé, ou tu en as trouvé un nouveau ? Mets à jour [docs/netypareo-api.md](docs/netypareo-api.md) dans la même pull request.

## ✅ Validation des contributions

Les pull requests sont relues et testées avant d'être fusionnées. Utilise les commentaires de la pull request pour suggérer des améliorations.

> ⚠️ Règle d'or : **aucune donnée personnelle dans le dépôt**. Pas d'identifiant ni de mot de passe, pas de lien iCal (il donne accès au planning sans mot de passe), pas de nom, d'adresse ou de numéro de contrat, pas de capture d'écran non anonymisée. Git garde tout dans son historique.

## 🔒 Les règles de sécurité

- **Les identifiants restent sur le téléphone**, dans le stockage sécurisé du système (`flutter_secure_storage`). Ils ne sont jamais écrits dans un journal.
- **Aucun serveur intermédiaire** : l'application parle directement à l'instance NetYParéo du CFA.
- **Le lien iCal est personnel.** Il est stocké comme un mot de passe et n'est jamais partagé.
- **Rien n'est codé en dur** : les numéros d'apprenant et d'inscription sont lus sur le site après la connexion.
- **Pas de martèlement du serveur** : les données sont mises en cache et la synchronisation reste espacée.

## ⚖️ Avertissement

Projet **non officiel**, sans lien avec YMAG ni avec le CFA. Chaque utilisateur se connecte avec son propre compte et ne voit que ses propres données.

## 📄 Licence

[MIT](LICENSE), copyright Olivier Dutoit et contributeurs.

---

<br>
Créé avec ❤️ en 2026 par Olivier Dutoit, promo BTS SIO 2026-2028 du CFAI LDA de Saint-Étienne.
