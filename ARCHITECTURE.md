# mUGGINFACE — architecture proposée (à valider)

App macOS native (Swift / SwiftUI), design Flat Mat clair/sombre, 4 langues (fr, en, es, it ; anglais par défaut).
Collection : DESKTOP MAC TOOLKIT. Dossier d'installation : Applications Personnelles. Version dev `….dev`.

## Modules
- **HardwareProbe** : puce, mémoire (sysctl), mémoire GPU utilisable (limite Metal ≈ 75 %), disque libre. Saisie manuelle possible.
- **HubClient** : API Hugging Face (`/api/models` : pipeline_tag, téléchargements, likes, licence, tailles safetensors/GGUF, dates). Jeton optionnel dans le Trousseau.
- **Benchmarks** : classements publics (Open LLM Leaderboard, MTEB, etc.) quand ils existent ; sinon indice téléchargements/likes/récence (marqué « estimé »).
- **FitEngine** : poids du fichier + cache KV + marge vs mémoire utilisable → Fluide / Compatible / Limite / Trop lourd, débit estimé. Score = performance × légèreté.
- **Catalog** (SQLite) : modèles, instantanés quotidiens, favoris, historique des changements.
- **Watcher** : scan quotidien en arrière-plan (login item), diff entre instantanés → nouveautés, montées, retraits ; notifications macOS.
- **Domains** : texte/chat, code, image, vidéo, voix/audio, vision, embeddings, traduction (correspondances pipeline_tag).
- **DownloadManager** : téléchargement intégré depuis le Hub (URLSession en arrière-plan, reprise après coupure, pause, file d'attente, vérification d'espace disque et de compatibilité avant, SHA-256 après, jeton Trousseau pour les modèles à accès restreint, dossier de destination réglable). Un modèle terminé peut être confié à l'agent pour un test.
- **AgentBridge** : discussion + envoi d'instructions à un agent IA choisi. Cibles : Claude Code (commande `claude -p` lancée dans le dossier choisi), Claude par API (clé dans le Trousseau), commande personnalisée. Le contexte (matériel, modèle, variante, dossier) est assemblé par l'app ; l'utilisateur relit et valide l'invite avant tout envoi ; l'agent garde ses propres autorisations ; aucune donnée personnelle hors matériel/modèle.
- **UI** : Recommandations, Détail, Veille, Réglages, À propos, menu de la barre de menus (ouverture par `popUp` sous l'icône, jamais `statusItem.menu`).
- **Updater** : modèle `mBACKUP/Sources/Updater.swift` (releases GitHub, signature Developer ID, case auto + bouton manuel).
- **Localisation** : String Catalog, mêmes clés dans les 4 langues, aucun texte en dur.

## Flux
Lancement → HardwareProbe → affichage du cache → Watcher (planifié ou manuel) → HubClient → Catalog (diff) → FitEngine → UI + notifications.

## Choix techniques
Réseau : URLSession seul, aucune donnée personnelle envoyée. Stockage local uniquement. Installation d'un modèle : téléchargement intégré ET envoi des instructions à un agent (les deux voies, au choix par variante) ; commande copiable en plus. Icône de la barre de menus : silhouette « m » en couleur (choix du 18/11/2026), avec progression des téléchargements.
