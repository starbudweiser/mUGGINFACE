# mUGGINFACE

## About
mUGGINFACE is a native macOS app (part of the DESKTOP MAC TOOLKIT) that lists the best Hugging Face AI models for your Mac, with constant monitoring. Pick your domains (text, code, image, video, voice, vision, embeddings, translation); the app detects your chip, memory and disk, scores each model by estimated performance and lightness, and warns when a model is too heavy. It can download a model itself (resume, SHA-256 check) or send the install instructions to an AI agent (Claude Code, Claude API, or a custom command). Languages: French, English, Spanish, Italian. Authors: Starbudweiser & Claude Code (Anthropic). MIT License, © 2026 Starbudweiser; provided as is, without warranty.

## Utilisation
- Lancer `./build_app.sh` (installe dans `~/Applications/Applications Personnelles`) ; `DEV=1 ./build_app.sh` construit la version de développement (`fr.stephan.mugginface.dev`, données séparées).
- Maquettes : `maquettes/`. Architecture : `ARCHITECTURE.md`.
- Les scores sont des estimations (taille, popularité, tendance, fraîcheur), pas des benchmarks officiels.
