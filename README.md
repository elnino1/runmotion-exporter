# RunMotion Exporter

Transforme une capture d'écran d'un plan RunMotion Coach en entraînement
fractionné structuré dans l'app Exercice de l'Apple Watch, via WorkoutKit,
sans compte Apple Developer payant.

Conception détaillée : [`docs/superpowers/specs/2026-09-23-runmotion-watch-export-design.md`](docs/superpowers/specs/2026-09-23-runmotion-watch-export-design.md).

Tout se passe sur l'iPhone : lecture de la capture par OCR (Vision) puis
analyse par Apple Intelligence (Foundation Models), sans aucun service en
ligne.

## Prérequis

- Un Mac avec **Xcode 26** ou plus récent.
- Un iPhone sous **iOS 26.5** ou plus récent, compatible Apple Intelligence
  (activé dans Réglages), jumelé à une Apple Watch.
- Un **identifiant Apple gratuit** (pas besoin du programme développeur
  payant).
- Un câble USB pour la première installation.

## Installation

### 1. Récupérer le projet

```bash
git clone <url-du-dépôt> runmotion_exporter
open runmotion_exporter/runmotion_exporter/runmotion_exporter.xcodeproj
```

### 2. Configurer la signature (une seule fois)

1. Xcode → **Settings… → Accounts** → **+** → ajouter ton identifiant
   Apple. Une équipe « *Ton Nom* (Personal Team) » apparaît.
2. Dans le projet, fais ceci pour **chacune des deux cibles**
   **runmotion_exporter** (l'app) et **runmotion_exporterShare** (l'extension
   de partage), onglet **Signing & Capabilities** :
   - **Team** : choisis ta *Personal Team*.
   - **Bundle Identifier** : il doit être unique au monde. Si Xcode
     affiche une erreur, remplace `com.in.runmotion-exporter` par quelque
     chose de personnel, par exemple `com.<ton-prénom>.runmotion-exporter`.
     L'extension doit garder le même préfixe suivi de `.share`, par exemple
     `com.<ton-prénom>.runmotion-exporter.share`.
   - Vérifie que la capacité **HealthKit** est présente. Elle est déjà
     déclarée dans les fichiers `.entitlements`. Si elle manque, ajoute-la
     avec **+ Capability → HealthKit**.

### 3. Préparer l'iPhone (une seule fois)

1. Branche l'iPhone au Mac en USB, déverrouille-le et accepte **« Faire
   confiance à cet ordinateur »**.
2. Active le **mode développeur** : Réglages → Confidentialité et
   sécurité → **Mode développeur** → activer, puis redémarre l'iPhone.
3. Dans Xcode, choisis ton iPhone comme destination (en haut de la
   fenêtre).

### 4. Installer l'app

1. Clique sur **Run** (▶, ou ⌘R).
2. Au premier lancement, iOS refuse d'ouvrir l'app tant que le
   développeur n'est pas approuvé. Va dans Réglages → Général → **VPN et
   gestion de l'appareil**, touche ton identifiant Apple puis
   **Faire confiance**.
3. Relance l'app.

### 5. Autoriser l'accès aux entraînements

Ouvre l'app **RunMotion Montre** une fois, touche **« Autoriser »** et
accepte la demande d'iOS. La ligne « Programmation sur la montre » doit
afficher « Autorisée ».

## Utilisation

1. Dans RunMotion, fais une capture d'écran du plan du jour.
2. Touche **Partager** (depuis l'aperçu de la capture ou depuis Photos),
   puis **RunMotion Montre**. S'il n'apparaît pas, touche **Plus** en bout
   de ligne et active-le.
3. L'OCR puis Apple Intelligence remplissent la liste des étapes.
   Vérifie-les : touche une étape pour corriger son type, sa durée ou sa
   vitesse. Tu peux aussi en ajouter, en supprimer ou les réordonner avec
   **Modifier**.
4. Choisis **Tapis** ou **Extérieur**, puis **« Envoyer à la montre »**.
5. Sur la montre, ouvre **Exercice**. La séance « RunMotion - Tapis » (ou
   « Extérieur ») apparaît parmi les entraînements programmés. Le transfert
   peut prendre quelques instants.

Chaque envoi remplace la séance précédente du même lieu, qui n'est donc
jamais dupliquée. Si la capture n'a pas pu être lue (Apple Intelligence
désactivé, capture inhabituelle…), l'écran s'ouvre vide et tu peux saisir
les étapes à la main.

L'app permet aussi d'**importer une capture** depuis Photos, de **saisir
une séance à la main** ou d'envoyer une **séance de test** de 4 minutes,
sans passer par le partage. Si l'envoi depuis l'extension échoue, passe
par l'app, qui fait la même chose. En dernier recours, **« Aperçu système
(ajout manuel) »** ouvre la fiche Apple de la séance pour l'ajouter à la
main dans Exercice.

## Tests

Les tests unitaires (cible `runmotion_exporterTests`) couvrent la
conversion en WorkoutKit, l'interprétation de la sortie d'Apple
Intelligence (répétitions, allures, plages de vitesse, distances) et le
regroupement des lignes d'OCR. Lance-les avec **⌘U** dans Xcode.

## Limites du compte gratuit

- **Validité de 7 jours** : passé ce délai, l'app ne s'ouvre plus tant
  qu'elle n'a pas été réinstallée depuis Xcode (étape 4). Les
  entraînements déjà programmés sur la montre restent disponibles. Ne
  supprime pas l'app avant de la réinstaller.
- **Sans câble** : une fois jumelé en USB, l'iPhone reste disponible dans
  Xcode par Wi-Fi (icône réseau à côté de son nom), à condition que le Mac
  et l'iPhone soient sur le même réseau.
- **Renouvellement automatique** : voir la section suivante.
- Un compte gratuit est limité à 3 apps installées en parallèle et
  10 identifiants d'app par semaine. L'extension de partage utilise un
  identifiant d'app en plus de celui de l'app.

## Réinstallation automatique

`scripts/reinstall-iphone.sh` recompile l'app avec un profil de signature
neuf et la réinstalle par Wi-Fi si la version installée expire dans moins
de 3 jours. `scripts/install-auto-reinstall.sh` le fait tourner chaque
jour à 12h30 via `launchd`. Si le Mac dort à cette heure-là, la
vérification a lieu au réveil. Une notification macOS indique le résultat.

Mise en place, une seule fois, dans le Terminal du Mac :

```bash
# 1. Xcode (et non les seuls Command Line Tools) doit être l'outil actif
xcode-select -p        # doit afficher …/Xcode.app/Contents/Developer
# sinon : sudo xcode-select -s /Applications/Xcode.app

# 2. Nom exact de l'iPhone
xcrun devicectl list devices

# 3. Premier passage manuel. Si macOS demande l'accès au trousseau pour
#    « codesign », choisis « Toujours autoriser ».
RUNMOTION_DEVICE="iPhone de David" scripts/reinstall-iphone.sh --force

# 4. Tâche quotidienne
scripts/install-auto-reinstall.sh "iPhone de David"
```

Conditions : session ouverte sur le Mac, Mac et iPhone sur le même Wi-Fi,
compte Apple toujours connecté dans Xcode → Settings → Accounts.
Journal : `~/Library/Logs/runmotion-reinstall.log`. Pour supprimer la
tâche : `scripts/install-auto-reinstall.sh --uninstall`.
