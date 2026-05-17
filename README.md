# LanguageAi

Application iOS SwiftUI pour parler avec une IA locale via Codex.

Le flux actuel est volontairement simple :
- iOS fait le speech-to-text avec `Speech`.
- iOS lit les réponses avec `AVSpeechSynthesizer`.
- Le backend local reçoit le texte, lance `codex exec`, puis renvoie une réponse JSON.
- L'app sait déjà afficher une action `display_image` dans la conversation.

## Prérequis
- Xcode 15+
- iOS 17.0+
- Node.js 20+
- Codex CLI connecté sur la machine qui lance le backend

## Lancer le backend

```bash
cd backend
npm start
```

Le backend écoute par défaut sur `http://127.0.0.1:3010`.

Variables utiles :
- `PORT=3010`
- `CODEX_BIN=codex`
- `CODEX_MODEL=<modele optionnel>`
- `CODEX_TIMEOUT_MS=120000`

## Lancer l'app iOS

Ouvre `LanguageAi.xcodeproj` dans Xcode, puis lance l'app sur simulateur.

Sur simulateur, `http://127.0.0.1:3010` pointe vers la machine hôte. Sur un iPhone physique, remplace `backendURL` dans `LanguageAi/ContentView.swift` par l'adresse IP locale du Mac, par exemple `http://192.168.1.20:3010/api/assistant`.

## Exemple de demande

Demande à voix haute ou au clavier :

```text
Montre-moi une image de la Tour Eiffel de nuit.
```

Codex doit répondre avec une action `display_image`; l'app l'affiche sous la réponse.
