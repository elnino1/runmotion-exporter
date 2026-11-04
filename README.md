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
git clone <url-du-dépôt> runmotion-exporter
```

Le projet Xcode n'est pas versionné : il est généré par XcodeGen depuis `project.yml`
(`brew install xcodegen`), comme pour les autres apps personnelles.

### 2. Signature

La compilation, la signature et l'installation sont gérées par **`../ios-updater`** : voir son
`README.md`. L'équipe (Personal Team) et le bundle id (`com.in.runmotion-exporter`, l'extension
utilisant `<bundle id>.share`) sont déclarés dans `../ios-updater/ios-updater.conf`, qui génère
`Config/Signing.local.xcconfig`. La capacité **HealthKit** est déclarée dans les fichiers
`.entitlements`.

### 3. Préparer l'iPhone (une seule fois)

1. Branche l'iPhone au Mac en USB, déverrouille-le et accepte **« Faire
   confiance à cet ordinateur »**.
2. Active le **mode développeur** : Réglages → Confidentialité et
   sécurité → **Mode développeur** → activer, puis redémarre l'iPhone.
3. Dans Xcode, choisis ton iPhone comme destination (en haut de la
   fenêtre).

### 4. Installer l'app

```bash
../ios-updater/ios-updater.sh --force runmotion-exporter
```

Au premier lancement, iOS refuse d'ouvrir l'app tant que le développeur n'est pas approuvé :
Réglages → Général → **VPN et gestion de l'appareil**, touche ton identifiant Apple puis
**Faire confiance**. Pour travailler dans Xcode : `open runmotion_exporter.xcodeproj` (après un
premier passage d'ios-updater, ou `xcodegen generate`).

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
regroupement des lignes d'OCR. Lance-les avec **⌘U** dans Xcode (`runmotion_exporter.xcodeproj` généré à la racine).

## Intégration continue

Workflows GitHub Actions standard (skill `github-ci`, dans `.github/workflows/`) :

| Workflow | Déclenchement | Rôle |
|---|---|---|
| `test.yml` (`Test`) | chaque push, toutes branches | génère le projet (XcodeGen), compile l'app et lance les tests unitaires sur un simulateur iPhone sans signature ; SwiftLint |
| `auto_pr.yml` | push sur une autre branche que `main` | ouvre (ou met à jour) une PR vers `main`, description tirée des commits |
| `release.yml` | `Test` réussi après un push sur `main` | tag semver (`feat:` → mineure, `BREAKING CHANGE` → majeure, sinon patch) + GitHub Release |

Réglage GitHub requis pour `auto_pr.yml` : Settings → Actions → General → Workflow permissions →
**Allow GitHub Actions to create and approve pull requests**. Messages de commit au format
Conventional Commits (`feat:`, `fix:`, `ci:`…), dont dépend la version.

SwiftLint (`.swiftlint.yml`, règles du skill apple-skills `ci-cd-setup`) : les violations existantes
sont gelées dans `.swiftlint-baseline.json`, seules les nouvelles font échouer la CI. En local :
`swiftlint lint --strict --baseline .swiftlint-baseline.json` (avec
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` si `xcode-select` pointe sur les Command
Line Tools). Après correction de violations anciennes : `swiftlint lint --write-baseline .swiftlint-baseline.json`.

Pas de déploiement TestFlight/App Store (compte Apple Developer payant requis) : l'installation sur
l'iPhone reste assurée par `../ios-updater`.

## Limites du compte gratuit

- **Validité de 7 jours** : passé ce délai, l'app ne s'ouvre plus tant
  qu'elle n'a pas été réinstallée (étape 4). Les
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

Assurée par `../ios-updater` (tâche launchd commune à toutes les apps, deux passages par jour,
renouvellement quand il reste moins de 72 h). Voir `../ios-updater/README.md`.
