# mUGGINFACE — documentation des fonctionnalités

Version décrite : 1.0.12 + volet Audit (en cours de validation). Application macOS native (Swift / SwiftUI), macOS 15 ou plus récent, Apple Silicon. Fait partie du DESKTOP MAC TOOLKIT. Langues : français, anglais, espagnol, italien (langue du système, anglais par défaut).

## 1. Principe

mUGGINFACE interroge l'API publique de Hugging Face, classe les modèles par domaine, calcule pour chacun s'il tient dans la mémoire de ton Mac, surveille les changements chaque jour, télécharge les modèles choisis et peut confier l'installation ou un test à un agent IA. Aucune donnée personnelle n'est envoyée : seules des requêtes publiques au Hub partent (le jeton Hugging Face, facultatif, reste dans le Trousseau).

## 2. Navigation

Barre latérale : Recommandations, Favoris, Veille, Audit, Téléchargements, Agent IA, Mon matériel, puis Réglages et À propos. La barre du haut indique l'état de la veille (point vert, dernier scan) et propose « Actualiser ». Une icône de barre de menus (silhouette « m » en couleur, avec progression des téléchargements) donne : Ouvrir, Actualiser maintenant, Réglages, À propos, Quitter. L'affichage Dock / barre de menus / les deux se règle dans Réglages.

## 3. Recommandations

- **Domaines** (plusieurs choix) : Texte / Chat, Code, Image, Vidéo, Voix / Audio, Vision, Embeddings, Traduction. Chaque domaine correspond à des étiquettes de pipeline du Hub (text-generation, text-to-image, text-to-video, text-to-speech, automatic-speech-recognition, image-text-to-text, feature-extraction, translation…).
- **Mon Mac (détecté)** : puce, mémoire utilisable, disque libre.
- **Filtres** : recherche par nom ; poids maximal (≤ 20 Go par défaut) ; licence libre seule ou toutes ; formats (MLX, GGUF, safetensors) ; tri par meilleur compromis, performance, légèreté, plus récents, popularité.
- **Ligne de modèle** : initiale, nom, auteur, licence, téléchargements, j'aime, étiquettes (Nouveau, Accès restreint, format), poids et RAM estimée, barre de poids, **score** sur 10 et **adéquation** (Fluide, Compatible, Limite, Trop lourd). Les modèles « Trop lourd » sont masqués par défaut.
- **Fiche détaillée** (clic sur une ligne) : score global et performance estimée, adéquation sur ce Mac (RAM sur mémoire utilisable, débit estimé en jetons par seconde pour les modèles de texte), caractéristiques (paramètres, j'aime, format, licence), **variantes installables** (une par quantification GGUF, ou dépôt complet) avec taille réelle lue dans la liste des fichiers du dépôt, commande d'installation copiable, favori, ouverture sur Hugging Face, « Télécharger », « Envoyer à l'agent » et « Demander à l'agent ».

## 4. Score et adéquation

- **Poids** : paramètres × bits de quantification (déduits du nom, des étiquettes et des métadonnées safetensors / GGUF) × 1,05 ; remplacé par la taille réelle des fichiers dès qu'elle est lue (jusqu'à 150 modèles par scan).
- **RAM nécessaire** = poids × 1,10 + 1,5 Go. **Mémoire utilisable** = mémoire totale − réserve système (16 Go par défaut, réglable).
- **Adéquation** : Fluide si RAM ≤ 60 % de la mémoire utilisable ; Compatible jusqu'à 85 % ; Limite jusqu'à 100 % ; Trop lourd au-delà.
- **Débit estimé** (modèles de texte) : débit mémoire de la puce × 0,7 ÷ poids, plafonné à 400 jetons/s. Débit mémoire déduit de la puce (M1 à M5, Pro / Max / Ultra).
- **Performance estimée** (0–10) : 30 % taille du modèle, 28 % j'aime, 22 % téléchargements, 10 % tendance, 10 % fraîcheur. **Score global** = 62 % performance + 38 % légèreté. Ce sont des estimations, pas des benchmarks officiels.

## 5. Favoris

Étoile sur la fiche d'un modèle ; le volet Favoris liste les modèles suivis avec les mêmes informations d'adéquation.

## 6. Veille

- Un scan par jour à l'heure choisie (9 h par défaut, minuterie vérifiée toutes les 10 minutes ; rattrapage si le Mac dormait) et un scan manuel.
- Pour chaque domaine, l'application garde le top 10 du jour et le compare au précédent : **Nouveau** (modèle jamais vu), **Entre** (entre dans le top 10), **Monte** (gagne au moins 2 rangs), **Retiré** (sort du top 10).
- Notification macOS (si activée) ; compteur de non-lus dans la barre latérale ; « Tout marquer comme lu ». Options : seulement mes domaines, seulement si compatible avec mon Mac.
- Le catalogue (près de 1 000 modèles en cache) et l'historique sont enregistrés localement dans `~/Library/Application Support/fr.stephan.mugginface/catalog.json`.

## 7. Audit de mes modèles (nouveau)

Objectif : un comparatif objectif entre les modèles réellement installés sur ce Mac et les meilleurs candidats du catalogue, avec suivi daté de l'évolution de l'atelier.

- **Détection** : cache Hugging Face (`~/.cache/huggingface/hub`, variables HF_HOME / HUGGINGFACE_HUB_CACHE), dossier des modèles de l'application (avec l'identifiant Hub des téléchargements terminés), Ollama (manifestes), LM Studio, et dossiers ajoutés dans le volet (un sous-dossier = un modèle). Les tailles suivent les liens vers les poids partagés sans les compter deux fois. Doublons fusionnés.
- **Identification** : identifiant exact du catalogue, sinon même nom de base (quantification et suffixes retirés), sinon fiche Hub du modèle (domaine déduit de l'étiquette de pipeline), sinon devinette par le nom, sinon « Hors catalogue ».
- **Comparaison** : pour chaque modèle connu, le meilleur candidat du même domaine **et de la même tâche** (une synthèse vocale n'est comparée qu'à des synthèses vocales), compatible avec la mémoire du Mac (pas « Trop lourd »), au moins 100 j'aime, hors variantes de la même famille et hors variantes non filtrées (uncensored, abliterated…), hors sous-tâches voisines (diarisation, détection de voix…). Verdict **À jour**, **Mieux disponible** (gain estimé d'au moins 15 %) ou **Hors catalogue**.
- **Mesuré ou estimé** : le gain vient de l'indice du Hub (marqué « estimé »). Quand la fiche du modèle publie des benchmarks (classements du Hub), le volet l'indique « mesuré » et, si le modèle installé et son candidat partagent un benchmark, affiche les deux valeurs côte à côte.
- **Indice d'atelier** : part moyenne du meilleur candidat atteinte par les modèles installés (100 % = rien de mieux). Il n'est calculé qu'avec les modèles connus.
- **Évolution** : un instantané par jour (le dernier du jour remplace le précédent), 120 conservés dans `audit.json`. Le volet trace les 14 derniers (courbe en barres), l'écart en points avec l'audit précédent et les modèles installés ou retirés depuis. Un audit se lance à la main (« Lancer l'audit »), à l'ouverture du volet si la liste est vide, et automatiquement après chaque veille quotidienne (au plus un par 20 heures ; case désactivable).
- Cliquer sur le candidat ouvre sa fiche dans Recommandations (téléchargement, envoi à l'agent).

### 7 bis. Analyse de l'agent et plan de mise à jour (nouveau)

Pour que l'audit ne reste pas des chiffres, un agent IA (celui choisi dans Réglages : Claude Code, Claude par l'API ou commande personnalisée) rédige l'analyse et prépare, si tu le veux, la mise à jour.

- **Analyser avec l'agent** : l'application envoie à l'agent l'audit (modèles installés, tailles, scores, verdicts, meilleurs candidats, benchmarks mesurés, matériel et indice d'atelier) ; aucune commande n'est exécutée. L'agent rédige, dans la langue de l'application, environ 350 mots : état général, priorités dans l'ordre, risques et réserves (licence, mémoire, estimations incertaines, qualité que les chiffres ne montrent pas), ce qu'il vaut mieux laisser, bénéfice attendu. L'analyse est conservée avec sa date et le nom de l'agent.
- **Plan de mise à jour** : tu coches les modèles à mettre à niveau, l'agent rédige un plan numéroté (téléchargement à côté de l'ancien modèle, test court, changements dans les fichiers d'instructions, note de retour) que tu **relis et modifies** dans l'application. Rien ne part sans ton accord.
- **Fichiers d'instructions du workflow** : tu ajoutes dans le volet les fichiers ou dossiers que le plan peut mettre à jour (par exemple un CLAUDE.md ou des skills). Seuls ceux-là, plus le journal `WORKFLOW-EVOLUTION.md` du dossier des modèles, peuvent être modifiés.
- **Exécution réversible** : avant d'envoyer le plan, l'application **sauvegarde elle-même** les fichiers d'instructions et le journal dans un dossier daté (`plans/<date>/backup`). L'agent reçoit des règles strictes : ne faire que le plan, ne jamais supprimer ni écraser un modèle existant (les nouveaux sont installés à côté), tester avant de changer une référence, noter chaque téléchargement dans `journal.json`, ajouter une entrée datée à `WORKFLOW-EVOLUTION.md` (ce qui change, ancien → nouveau, retour). Claude Code n'a le droit d'écrire que dans ces fichiers (règles d'autorisation `Edit` ciblées), avec un délai maximal de 45 minutes. L'exécution demande Claude Code ou une commande personnalisée : l'API seule ne peut pas agir sur ce Mac.
- **Annuler cette mise à jour** : après confirmation, l'application restaure les fichiers d'instructions depuis la sauvegarde (la version modifiée est gardée à côté, dans `replaced/`), retire les fichiers créés par le plan et met à la **corbeille** les dossiers de modèles notés dans le journal, uniquement s'ils sont dans le dossier des modèles, le cache Hugging Face ou un dossier analysé. Les anciens modèles n'ont jamais été touchés. L'historique des mises à jour (date, statut Préparé / Exécuté / Échec / Annulé, résultat) est visible dans le volet, avec « Afficher le dossier ».
- Limite : le retour arrière ne défait que ce qui est sauvegardé ou noté dans le journal ; ce que l'agent ferait en dehors des règles (installer un outil, par exemple) n'est pas annulé automatiquement.

## 8. Téléchargements

- Téléchargement intégré depuis le Hub : file d'attente (un à la fois), pause, reprise après coupure (Range, fichier `.part`), progression, débit, temps restant, « Afficher » dans le Finder.
- **Avant** : espace disque suffisant, compatibilité avec le Mac, jeton Hugging Face pour les modèles à accès restreint (jamais transmis à un autre domaine lors des redirections). **Après** : vérification SHA-256 de chaque fichier, puis proposition de tester via l'agent.
- Destination : `<dossier des modèles>/<nom du modèle>` (par défaut `~/Modèles`, réglable).

## 9. Agent IA

- Discussion avec contexte (Mac, domaines, meilleurs candidats) pour choisir un modèle ; les identifiants cités deviennent des liens vers la fiche.
- **Installation / test confiés à un agent** : l'application assemble l'invite (matériel, modèle, variante, dossier), l'utilisateur la relit, puis elle part. Cibles : Claude Code (`claude -p` dans le dossier de travail), Claude par l'API (clé dans le Trousseau) ou commande personnalisée (invite sur l'entrée standard). L'agent agit avec ses propres autorisations ; rien ne part sans clic (réglage « Confirmer avant d'envoyer »).

## 9 bis. Mon matériel

Puce, mémoire, mémoire utilisable, disque libre, débit mémoire estimé. Réglages : mémoire réservée au système (4 à 64 Go), mémoire saisie manuellement (pour comparer avec un autre Mac).

## 10. Réglages

Langue (automatique), apparence (auto / clair / sombre), affichage Dock et/ou barre de menus, lancement à l'ouverture de session, dossier des modèles, jeton Hugging Face (Trousseau), agent par défaut, confirmation avant envoi, mises à jour automatiques et manuelles.

## 11. Mises à jour et À propos

Recherche quotidienne dans les releases GitHub, vérification de la signature Developer ID, remplacement et relance (jamais pendant un téléchargement). Fenêtre « À propos » : version, collection DESKTOP MAC TOOLKIT, auteurs, licence MIT.

## 12. Données et vie privée

Tout est local : `catalog.json` (catalogue, favoris, événements), `downloads.json` (file de téléchargements), `audit.json` (instantanés d'audit), `audit-agent.json` (dernière analyse, historique des plans), `plans/<date>/` (sauvegardes, journal), préférences utilisateur, Trousseau (jetons). Aucun compte, aucune télémétrie. L'audit lit les dossiers de modèles de ce Mac (noms et tailles) sans rien envoyer : seuls les identifiants de modèles Hub partent dans des requêtes publiques de fiche.

## 13. Limites connues

Scores estimés (sauf benchmarks publiés dans les fiches) ; le tri favorise la popularité ; poids et RAM approximatifs tant que la taille réelle n'est pas lue ; l'audit ne compare pas la qualité mesurée sur tes propres usages (un banc d'essai local est une évolution possible).
