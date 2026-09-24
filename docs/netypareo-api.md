# NetYParéo — carte des endpoints (instance CFAI / Cité des Entreprises)

Exploration faite le 23/09/2026 sur un compte **apprenant**, NetYParéo **v3.34.16** (éditeur YMAG).

- Base URL : `https://netypareo.citedesentreprises.org/netypareo/index.php`
- Il n'y a **pas d'API REST officielle**. C'est une application PHP rendue côté serveur, avec des appels AJAX jQuery. Selon l'endpoint, la réponse est une page HTML complète, un fragment HTML, du JSON ou un PDF.
- **Encodage** : les réponses HTML sont en `windows-1252` et les réponses JSON en `UTF-8`. Côté Dart, décoder avec `latin1`/`Windows1252Codec` (package `enough_convert` ou `charset`) selon le `content-type`.
- Les appels AJAX envoient `X-Requested-With: XMLHttpRequest`. Les POST sont en `application/x-www-form-urlencoded`.
- Les URLs se terminent souvent par `/`. Il faut suivre exactement les formes ci-dessous, sinon le serveur répond 404.
- Chaque page déclare ses routes AJAX via `application.setRoutes([...])` dans un `<script>` inline : `{name:"@route", pathinfo:"/x/y/", parameters:[...]}`. Les paramètres sont concaténés au pathinfo, séparés par `/`. C'est pratique pour redécouvrir les routes après une mise à jour.

## Identifiants métier

| Nom | Exemple | Où le trouver |
|---|---|---|
| `codeApprenant` (= `codeRessource` pour le type 7500) | `1234567` | liens `/apprenant/bulletin/{code}/`, `/apprenant/calendrier/{code}/` sur l'accueil |
| `codeInscription` | `1234569` | champ caché `codeInscription` du formulaire Assiduité / Calendrier / Relevé |
| `typeRessource` | `7500` = apprenant | constantes JS |
| `numSemaine` | `202639` (AAAA + n° ISO) | planning |
| `codeSeance` | `16572631` | JSON du planning |
| `codeMatiere` | `13404351` | `metadatas.codeMatiere` du planning, `listeMatieresParPeriode` |
| `codeGroupe` | `16456945` | `metadatas.codesGroupes` |

Le paramètre `ressources` du planning est du base64 de `[{"code":<codeApprenant>,"type":7500}]`.

---

## 1. Authentification et session

### Login
`GET /` : la page de login. Il faut en extraire `token_csrf` (champ caché, qui change à chaque chargement).

`POST /authentication/` (form-urlencoded) :

| Champ | Valeur |
|---|---|
| `login` | identifiant |
| `password` | mot de passe |
| `screenWidth` / `screenHeight` | taille d'écran (optionnel, vide accepté par le formulaire) |
| `token_csrf` | valeur extraite de la page de login |
| `btnSeConnecter` | présent (bouton submit) |

- La session repose sur un cookie **HttpOnly**, invisible depuis JS (probablement `PHPSESSID`). Il faut un cookie jar persistant, par exemple `dio` + `cookie_jar`.
- Le cookie de session doit sans doute exister **avant** le POST. Faire donc d'abord le `GET /`, puis le POST avec les mêmes cookies.
- Une fois connecté, le serveur redirige vers `/apprenant/accueil`. En cas d'échec : `/login/{codeErreur}`.
- **2FA possible** : le JS de connexion contient un module `TwoFaVerify` (code OTP à N chiffres, renvoi par SMS, `token_csrf` dans `#js-twofa-region`). Il n'a pas été déclenché sur ce compte, mais l'app doit détecter l'écran OTP (`#twofa-form`, `.js-twofa-digit`) et savoir le gérer.
- ⚠️ Le flow POST n'a pas été capturé en direct : l'utilisateur s'est connecté lui-même. À valider pendant le développement.

### Keep-alive
`GET /rester-connecter/` renvoie `{"status":"success"}` et prolonge la session. La page affiche une alerte avant expiration : à appeler périodiquement.

### Logout
`GET /logout/`

### Session expirée
Toute page protégée redirige vers la page de login. Détecter la présence de `form[action$="/authentication/"]` dans la réponse, puis se reconnecter.

---

## 2. Planning ⭐

### Flux iCalendar (sans session !)
`GET /planning/ical/{UUID}/` renvoie `text/calendar; charset=utf-8` et fonctionne **sans cookie**.
- Contient toute l'année : `SUMMARY` = « MATIERE - Formateur(s) », `LOCATION` = salle, `DESCRIPTION` = groupe, `UID` = `{codeApprenant}{codeSeance}@NetYpareo`.
- L'UUID est personnel et secret. On l'obtient via `GET /planning/modal-icalendar-ressource/7500/{codeApprenant}` (fragment HTML ; chercher l'URL `.../planning/ical/...`). Il existe aussi la route `@modalICalendar` → `/planning/modal-icalendar/` dans Paramètres utilisateur.
- 👉 C'est la meilleure source pour l'emploi du temps : il suffit de le récupérer une fois, puis de synchroniser sans login et en arrière-plan.

### Planning JSON (avec session)
`GET /apprenant/planning/courant/?semaineDebut={numSemaine}&semaineFin={numSemaine}&ressources={b64}&modeAffichage=0`
Page HTML dont un `<script>` contient `var planningJSON = {...};`. C'est du JSON structuré :

```json
{
  "configuration": {"minuteDebut":480,"minuteFin":1080,"jours":[1,2,3,4,5], ...},
  "semaines": [{
    "code": 202639, "libelle": "Semaine 39", "dateDebut": "21/09/2026",
    "ressources": [{
      "code": 1234567, "type": 7500, "libelle": "M. NOM Prénom",
      "seances": [{
        "code": 16572631, "type": 81500, "couleur": "#00FF80",
        "libelle": "MATHEMATIQUES / ALGO",
        "numJour": 3, "minuteDebut": 600, "duree": 120, "numSemaine": 202639,
        "detail": ["M. FORMATEUR", "(CITE) SALLE", "Groupe1, Groupe2"],
        "icones": [{"libelle":"Cahier de textes saisi sur la séance","classe":"icon picto-green-c"}],
        "metadatas": {"codeMatiere":13404351,"coeff":1,"codesGroupes":[16456945,16456946]}
      }],
      "contraintes": [{"numJour":1,"minuteDebut":0,"duree":480,"type":154, ...}]
    }]
  }]
}
```
`numJour` : 0 = dimanche, 1 = lundi… `minuteDebut` = minutes depuis minuit.

### Planning d'un jour (JSON)
`GET /planning/jour/ajax/{JJ}/{MM}/{AAAA}` renvoie le même format que `planningJSON`, pour un seul jour. Il est utilisé par le widget de l'accueil.

### Jours ayant des cours (JSON)
`GET /planning/datepicker/infos/{typeRessource}/{codeRessource}/{JJ-MM-AAAA début}/{JJ-MM-AAAA fin}/{afficherDatesActions=1}/{afficherDatesSeances=1}`
```json
{"typeRessource":7500,"codeRessource":1234567,"dateDebut":"01/09/2026","dateFin":"31/10/2026","jours":["14/09/2026","15/09/2026", ...]}
```

### Détail d'une séance (HTML)
`GET /planning/seance/{codeSeance}/{typeRessource}/{codeRessource}` renvoie un fragment HTML de modale : matière, horaires, groupes, formateurs, salles, matériel, visio, commentaire, **contenu du cahier de textes**, éléments abordés, ressources pédagogiques.

### Autres
- `GET /planning/modal/rappels/modifications/{numSemaine?}` : historique des modifications du planning (HTML)
- `GET /planning/historique/modal/{numSemaine}` : historique
- `GET /groupe/modal/{codeGroupe}` : infos du groupe
- `GET /planning/json/` : route déclarée, pas testée

---

## 3. Accueil / fil d'actualités

- `GET /apprenant/accueil` : fil d'actualités initial (HTML, `.newsfeed-group[data-date]`), widget du planning du jour, dernières évaluations, absences, contacts.
- `POST /apprenant/fil-actualites/` avec `dateReference=JJ/MM/AAAA` : suite du fil, en scroll infini (fragment HTML ; `.newsfeed-nodata` quand il n'y a plus rien).
- Pièces jointes : `GET /document/telecharger/{token}/`. Le token est opaque et se trouve dans le HTML.

---

## 4. Calendrier de formation (présence centre / entreprise)

- `GET /apprenant/calendrier/` : page. `var itemsInfos = [{identifiant:153,...}]` = légende des types de journée.
- `GET /apprenant/calendrier/detail/json/{codeInscription}/{numSemaine}` → JSON :
  ```json
  {"creneaux":[{"jour":"21/09/2026","creneaux":[150,150,...,151,151]}, ...]}
  ```
  Un code par demi-heure. `150`/`151`/`153` : types (centre, entreprise, férié…), dont le mapping est à déduire de la légende HTML de la page.
- `GET /apprenant/calendrier/{codeApprenant}/` (HTML) : toute l'année d'un coup, c'est ce que lit l'application.
  - Chaque jour : `<a data-date="dd/MM/yyyy" data-identifiant="150" style="background-color: rgb(r,g,b)">`. Les jours sans type (week-ends, hors période) n'ont pas de `data-date`.
  - Légende : `.legende-item` > `.legende-item-color` (`background-color: #RRGGBB`) + `.legende-item-text`.
  - Sur l'instance explorée : `150` = « Présence au centre de formation » (#A8FFA8), `153` = « Présence en entreprise » (#FF8080), `151` = « Créneaux indisponibles » (#FF7D7D, ex. jours fériés). Les codes dépendent du CFA : l'application relie chaque jour à son libellé **par la couleur** de la légende, pas par le code.
  - Titre : « Calendrier du dd/MM/yyyy au dd/MM/yyyy ».
- `GET /apprenant/calendrier/pdf/{codeApprenant}/{codeInscription}/0/` : PDF du calendrier.

---

## 5. Assiduité (absences)

- `GET /apprenant/assiduite/`, ou `POST /apprenant/assiduite/{codeApprenant}/` avec `codeInscription`.
- HTML : tableau « Du / Au / Durée / Motif / Détail ». Le texte « Aucune absence constatée. » apparaît quand il n'y en a pas. **À parser.**
- Le bulletin contient aussi la liste des absences.

---

## 6. Évaluation (notes)

Aucune note n'était saisie au moment de l'exploration. Les formats de réponse sont **à vérifier** plus tard.

### Relevé de notes
- `GET /evaluation/releve-notes/apprenant/`, ou `POST /evaluation/releve-notes/apprenant/{codeApprenant}/` avec `codeInscription`.
- Inline : `var listeMatieresParPeriode = [{codePeriodeEvaluation:-1, nomPeriodeEvaluation:"Année scolaire", listeMatieres:[{codeMatiere, nomMatiere, nomNetMatiere, abregeMatiere, codeTypeMatiere, couleur, ...}]}]` (JSON, **liste des matières**).
- Routes AJAX :
  - `@listeDevoirsInscriptionParMatiere` → `/evaluation/releve-notes/liste-devoirs-inscription-par-matiere/{codeInscription}/{codePeriodeEvaluation?}/{codeMatiere?}` (liste des devoirs, via `AjaxView` → HTML)
  - `@exportReleveNotesInscription` → `/evaluation/releve-notes/inscription/export/{codeInscription}/{codePeriodeEvaluation?}/{codeMatiere?}` (export tableur)
  - `@pdfReleveNotesInscription` → `/evaluation/releve-notes/inscription/pdf/{codeInscription}/{codePeriodeEvaluation?}/{codeMatiere?}`
  - Ces trois routes renvoient 404 pour l'instant, probablement parce qu'il n'y a encore aucune période ni aucune note. À retester.

### Bulletin
- `GET /apprenant/bulletin/{codeApprenant?}/{codeInscription?}/{codePeriode?}` (HTML) : moyennes, appréciations, absences.
- `GET /apprenant/detail-notes/{codeInscription}/{codeMatiere}/{codePeriodeEvaluation}` : modale avec le détail des notes d'une matière.

---

## 7. Pédagogie

### Cahier de textes
- `GET /pedagogie/apprenant/bilan/consultation-libre-cdt/` : contenu du cahier de textes par séance (HTML). Il faut le parser : matière, titre, « Séance du … de … à … par … », contenu, pièces jointes `/document/telecharger/{token}/`.
- `POST /pedagogie/apprenant/bilan/consultation-libre-cdt/{codeApprenant}/` : filtres (`modeFixeDeb`, `modeFixeFin` au format JJ/MM/AAAA, `modeGlissantDeb`, `modeGlissantFin` en semaines).
- **PDF** : `GET /pedagogie/cahier-de-textes/contenu/impression/apprenant/amplitude/{codeApprenant}/{JJ-MM-AAAA}/{JJ-MM-AAAA}/` renvoie `application/pdf` ✅
- `GET /pedagogie/cahier-de-textes/contenu/impression/apprenant/periode/{codeApprenant}/{codeNetPeriodePeda}`
- `@bilanCdtContenuAnnuelApprenantAjax` → `/pedagogie/cahier-de-textes/bilan/apprenant/contenu/annuel/{codeApprenant}/{codeNetPeriodePeda}` (bilan par période ; 404 avec `-1`, il faut une vraie période)
- `GET /pedagogie/apprenant/bilan/cahier-de-textes/periodes/` : liste des périodes pédagogiques (vide pour l'instant)
- Le détail d'une séance (`/planning/seance/...`) contient aussi le cahier de textes.

### Travail à faire
- `GET /travail-a-faire/` : page
- `POST /travail-a-faire/vue/agenda/` avec `codeMatiere` (vide = toutes) : vue agenda (HTML)
- `POST /travail-a-faire/vue/calendrier/` avec `dateReference=01/MM/AAAA` : vue mensuelle (HTML)
- `POST /travail-a-faire/infinite-scroll/` avec `codeApprenant`, `currentPage`, `dateEnCours` (JJ/MM/AAAA), `codeMatiere`, `afficherRetards` (0/1) : travaux précédents
- ✏️ Actions en écriture (non testées) :
  - `POST /travail-a-faire/declarer-fait/` avec `codeNetTravailAFaire`, `codeApprenant`
  - `POST /travail-a-faire/supprimer-travail/`
  - `GET /travail-a-faire/modale-rendre-taf/{codeNetTravailAFaire}/{codeApprenant?}/{isModification?}` (rendu de devoir / upload)

### Documents de liaison
- `GET /pedagogie/documents-liaison/lister/{codeDocLiaisonDepot?}/{isSelection?}`
- `POST /pedagogie/documents-liaison/lister-ressource/ajax/` renvoie un **JSON** (liste de dépôts). Body :
  - `filtrePublication=all`, `filtreDocument=all`
  - `periodePublication=dates` (ou `7`, `15`, `30`, `90` jours)
  - `dateDebRecherche` / `dateFinRecherche` au format `JJ/MM/AAAA` (le format ISO donne une erreur 500)
  - Champs lus par le site : `codeNetDocLiaisonDepot`, `nomDepot`, `dateCreation`, `emetteur{abregeCivilite, nom, prenom}`, `isARetourner`, `dateLu`, `dateRetour`, `dateEcheance`, `nbLus`, `nbRetournes`.
- `GET /pedagogie/documents-liaison/detail/{codeDocLiaisonDepot}`
- ✏️ `/pedagogie/documents-liaison/deposer/{code?}`, `POST /pedagogie/documents-liaison/delete-liste-depots/`

---

## 8. Documents (GED)

- `GET /apprenant/documents/` : explorateur. Inline : `var currentFsParams = '<b64>'`, qui décode en `{"i":{"typeRessource":7500,"codeRessource":...,"metadatas":[]},"m":"$2y$04$...","t":"FileSystemContextMultiple"}`. `m` est une **signature bcrypt régénérée à chaque chargement**, donc à extraire de la page juste avant l'appel.
- `POST /document/liste/` : contenu d'un dossier (fragment HTML, tableau) :
  - `explorerId=explorer-app-{codeApprenant}`
  - `fsParams={currentFsParams}`
  - `showFileMenu=1`
  - `path=` base64 de `["NomDossier", sousDossierId|null]`, par exemple `["Préinscription",null]`. Racine = `[null,null]`.
  - Chaque ligne a `data-resource-type` (directory/file), `data-file-system-params` et `data-file-system-path`.
  - Dossier : `title` = nom, `.text-small` = « (7) » quand le site annonce un nombre de fichiers. La ligne « dossier précédent » porte l'icône `.document-level-up`.
  - Fichier : lien `/document/telecharger/`, icône `document-pdf`, `document-image`…, colonnes Type (3e), Contexte, Créateur, Modifié le (6e, « 27/04/2026 à 16:19 »).
  - Pour ouvrir un sous-dossier : rappeler `/document/liste/` avec le `fsParams` et le `path` de sa ligne.
- `/document/liste/recherche/` (recherche), `/document/liste/documents-recents/` (POST, 404 en GET)
- Téléchargement : `GET /document/telecharger/{token}/`
- ✏️ `/document/renommer/`, `/document/televerser/modal/{id?}/{nbMaxDocument?}`

---

## 9. Profil / formation

- `GET /apprenant/details/` : identité, coordonnées, responsable légal, formation, contrat, entreprise, tuteur (HTML).
- `GET /coordonnees/` : coordonnées (+ bancaires).
- `GET /entreprise/details/{codeEntreprise}/`, `/entreprise/modal/{codeEntreprise}`, `/formation/modal/{codeFormation}`, `/apprenant/contrat/missions/modal/{codeContrat}`
- **Photo** : `GET /apprenant/photo/{taille}/{codeApprenant}/` (ex. taille `54`) ; formateurs : `/personnel/photo/{taille}/{codePersonnel}`
- `GET /parametres/utilisateur/` : identifiant, première et dernière connexion. ✏️ changement de mot de passe (formulaire avec `antiCSRFToken`, `currentPassword`, `password`, `confirm` ; 10 caractères minimum dont un spécial).
- `GET /apprenant/candidature/`, `/apprenant/candidature/suivi/`, `/apprenant/candidature/recapitulatif/pdf/`, `/candidat/renseignements/`, `/candidat/documents/`

---

## 10. Émargement
- `@ajaxHasEmargementOuvert` → `/emargement/ajax/has-emargement/` (404 en GET, probablement POST ou seulement pendant une séance)
- `@modalEmargementApprenant` → `/emargement/modal/emargement-ouvert/`
- Utile pour une notification « émargement ouvert ». À retester pendant un cours.

---

## Recommandations pour l'app Flutter

1. **Emploi du temps** : utiliser le **flux iCal** (sans session, robuste). Il faut juste le récupérer une fois après le login. Compléter avec `/planning/jour/ajax/` ou `planningJSON` pour les couleurs, `codeSeance` et `codeMatiere`, puis `/planning/seance/...` pour le détail et le cahier de textes.
2. **Client HTTP** : `dio` + `cookie_jar` persistant + décodage windows-1252 + détection de session expirée avec relogin automatique. Le mot de passe doit être stocké dans `flutter_secure_storage`.
3. **Parsing HTML** : package `html` (`package:html/parser.dart`) pour absences, bulletin, cahier de textes, travail à faire et documents. Les routes utiles sont dans les `setRoutes([...])` inline : les parser dynamiquement pour résister aux mises à jour.
4. **Keep-alive** : `GET /rester-connecter/` quand l'app est au premier plan.
5. Toujours lire les identifiants (`codeApprenant`, `codeInscription`) sur les pages après le login ; ne jamais les coder en dur.

## Reste à explorer
- Capture réelle du POST `/authentication/`, de la redirection et du nom du cookie, puis de l'écran 2FA s'il apparaît.
- Formats des notes et du bulletin une fois des notes saisies.
- Structure HTML du détail d'un document de liaison (aucun document sur le compte de test).
- Mapping des codes 150/151/153 du calendrier.
- Émargement pendant un cours.
