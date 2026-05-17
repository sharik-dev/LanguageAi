import http from "node:http";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const port = Number(process.env.PORT ?? 3010);
const codexBin = process.env.CODEX_BIN ?? "codex";
const codexModel = process.env.CODEX_MODEL;
const requestTimeoutMs = Number(process.env.CODEX_TIMEOUT_MS ?? 120000);

const server = http.createServer(async (req, res) => {
  setCorsHeaders(res);

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    sendJSON(res, 200, { ok: true, service: "languageai-backend" });
    return;
  }

  if (req.method === "POST" && req.url === "/api/assistant") {
    try {
      const body = await readJSON(req);
      const message = String(body.message ?? "").trim();

      if (!message) {
        sendJSON(res, 400, { error: "message is required" });
        return;
      }

      const response = await askCodex(message);
      sendJSON(res, 200, normalizeAssistantResponse(response, message));
    } catch (error) {
      console.error(error);
      sendJSON(res, 500, {
        message: "Le backend local a rencontre une erreur avec Codex.",
        speak: "Je n'ai pas reussi a contacter Codex.",
        actions: [],
        error: error.message
      });
    }
    return;
  }

  sendJSON(res, 404, { error: "not found" });
});

server.listen(port, "0.0.0.0", () => {
  console.log(`LanguageAi backend listening on http://127.0.0.1:${port}`);
});

function setCorsHeaders(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
}

function sendJSON(res, status, payload) {
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

async function readJSON(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  return raw ? JSON.parse(raw) : {};
}

async function askCodex(userMessage) {
  const dir = await mkdtemp(join(tmpdir(), "languageai-codex-"));
  const outputFile = join(dir, "response.txt");
  const prompt = buildPrompt(userMessage);

  try {
    await writeFile(outputFile, "", "utf8");

    const args = [
      "exec",
      "--ephemeral",
      "--sandbox",
      "read-only",
      "--output-last-message",
      outputFile
    ];

    if (codexModel) {
      args.push("--model", codexModel);
    }

    args.push(prompt);

    await runCodex(args);
    const raw = await readFile(outputFile, "utf8");
    return parseCodexJSON(raw);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

function runCodex(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(codexBin, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: process.env
    });

    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(new Error(`Codex timeout after ${requestTimeoutMs}ms`));
    }, requestTimeoutMs);

    child.stderr.on("data", chunk => {
      stderr += chunk.toString("utf8");
    });

    child.on("error", error => {
      clearTimeout(timer);
      reject(error);
    });

    child.on("close", code => {
      clearTimeout(timer);
      if (code === 0) {
        resolve();
      } else {
        reject(new Error(stderr.trim() || `Codex exited with code ${code}`));
      }
    });
  });
}

function buildPrompt(userMessage) {
  return `Tu es Jarvis pour une app iOS vocale en francais.
Reponds uniquement avec un objet JSON valide, sans markdown.
Schema exact:
{
  "message": "reponse visible courte en francais",
  "speak": "phrase courte a lire a voix haute",
  "actions": [
    {
      "type": "display_image",
      "title": "titre optionnel",
      "query": "requete visuelle optionnelle",
      "image_url": "url https optionnelle"
    }
  ]
}

Regles:
- Si l'utilisateur demande a voir, afficher, montrer, ouvrir une image, une photo, un schema ou une illustration, ajoute une action display_image.
- Si tu connais une URL d'image directe et stable, mets-la dans image_url. Sinon laisse image_url absent et mets une query utile.
- Pour les autres demandes, actions doit etre [].
- Ne promets pas d'action systeme non implementee. Explique brievement ce que tu peux faire.

Demande utilisateur: ${JSON.stringify(userMessage)}`;
}

function parseCodexJSON(raw) {
  const trimmed = raw.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const match = trimmed.match(/\{[\s\S]*\}/);
    if (!match) {
      throw new Error(`Codex returned non JSON output: ${trimmed.slice(0, 200)}`);
    }
    return JSON.parse(match[0]);
  }
}

function normalizeAssistantResponse(response, userMessage) {
  const actions = Array.isArray(response.actions) ? response.actions : [];
  return {
    message: String(response.message ?? "J'ai traite ta demande."),
    speak: typeof response.speak === "string" ? response.speak : undefined,
    actions: actions.map(action => normalizeAction(action, userMessage)).filter(Boolean)
  };
}

function normalizeAction(action, userMessage) {
  if (!action || action.type !== "display_image") {
    return null;
  }

  const query = String(action.query ?? action.title ?? userMessage).trim();
  const normalized = {
    type: "display_image",
    title: action.title ? String(action.title) : query,
    query
  };

  if (typeof action.image_url === "string" && action.image_url.startsWith("https://")) {
    normalized.image_url = action.image_url;
  } else if (query) {
    normalized.image_url = buildFallbackImageURL(query);
  }

  return normalized;
}

function buildFallbackImageURL(query) {
  const terms = query
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9 ]/g, " ")
    .trim()
    .split(/\s+/)
    .slice(0, 5)
    .map(encodeURIComponent)
    .join(",");

  return `https://loremflickr.com/1200/800/${terms || "image"}`;
}
