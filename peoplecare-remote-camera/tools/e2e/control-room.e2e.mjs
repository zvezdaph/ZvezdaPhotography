// Control Room scenario for the local end-to-end check (tools/e2e/run_e2e.sh):
// drives the real Control Room in Chromium against `wrangler dev`, while the
// phone side runs the real Dart layer (apps/remote_camera/test_e2e).
import { chromium } from "playwright-core";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";

const base = process.env.E2E_BASE ?? "http://127.0.0.1:8787";
const mockApi = process.env.E2E_MOCK_API ?? "http://127.0.0.1:8788";
const password = process.env.E2E_PASSWORD;
const codeFile = process.env.E2E_CODE_FILE;
const doneFile = process.env.E2E_DONE_FILE;
const shots = process.env.E2E_SCREENSHOTS ?? "build/e2e";
if (!password || !codeFile || !doneFile) throw new Error("E2E_PASSWORD, E2E_CODE_FILE and E2E_DONE_FILE are required");

const log = (message) => console.log(`[control-room] ${message}`);
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForFile(path, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (!existsSync(path)) {
    if (Date.now() > deadline) throw new Error(`timeout waiting for ${path}`);
    await sleep(200);
  }
  return (await readFile(path, "utf8")).trim();
}

await mkdir(shots, { recursive: true });
const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH || undefined });
const context = await browser.newContext({ viewport: { width: 1600, height: 1050 }, colorScheme: "dark" });
const page = await context.newPage();
page.setDefaultTimeout(30_000);
page.on("console", (msg) => {
  if (msg.type() === "error") console.log(`[browser] ${msg.text()}`);
});

// Waits until the command feed shows the command as acknowledged by the phone.
async function acked(label) {
  await page.locator(".command-feed li.cmd-completed", { has: page.locator(".cmd-name", { hasText: new RegExp(`^${label.replace(/[+]/g, "\\+")}$`) }) }).first().waitFor();
  log(`ACK completed: ${label}`);
}

try {
  // 1. Login
  await page.goto(base);
  await page.getByLabel("Operatore").fill("Regia E2E");
  await page.getByLabel("Password regia").fill(password);
  await page.getByRole("button", { name: "Entra in regia" }).click();
  await page.getByRole("heading", { name: "Multicamera" }).waitFor();
  log("login ok");
  await page.screenshot({ path: `${shots}/01-dashboard.png` });

  // 2. Pairing with the code shown by the phone
  const code = await waitForFile(codeFile, 90_000);
  log(`pairing code from the phone: ${code}`);
  await page.getByRole("button", { name: "＋ Aggiungi camera", exact: true }).click();
  await page.getByLabel("Codice dispositivo").fill(code);
  await page.getByLabel("Nome camera").fill("CAM 01 - SALA");
  await page.screenshot({ path: `${shots}/02-add-camera.png` });
  await page.getByRole("button", { name: "Associa camera" }).click();
  await page.getByRole("heading", { name: "CAM 01 - SALA" }).waitFor();
  await page.locator(".detail-title").getByText("ONLINE", { exact: true }).waitFor();
  log("camera paired and online");

  // 3. START from the Control Room: real ACK from the phone, LIVE only when the phone reports it
  await page.getByRole("button", { name: "START", exact: true }).click();
  await acked("Avvio stream");
  await page.locator(".preview-tally").waitFor();
  log("phone reports LIVE");

  // Cloudflare sees the ingest (mocked Stream API status), picked up by the Worker's poll
  const inputs = await (await fetch(`${mockApi}/__mock/inputs`)).json();
  if (inputs.length !== 1) throw new Error(`expected 1 live input, found ${inputs.length}`);
  await fetch(`${mockApi}/__mock/status`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ uid: inputs[0].uid, status: "connected" }),
  });

  // 4. Camera controls
  await page.locator(".slider-row", { hasText: "Zoom" }).getByRole("button", { name: "+" }).click();
  await acked("Zoom +");
  await page.locator(".slider-row", { hasText: "Zoom" }).getByText("1.5×").waitFor();
  await page.getByRole("button", { name: "TORCH OFF" }).click();
  await acked("Torcia");
  await page.getByRole("button", { name: "TORCH ON" }).waitFor();
  await page.getByRole("button", { name: "FRONT CAMERA" }).click();
  await acked("Cambio camera");
  // The front lens has no flash: the Control Room disables the torch (capabilities).
  await page.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent?.includes("TORCH") && b.disabled));
  log("torch disabled on the front camera");
  await page.getByRole("button", { name: "REAR CAMERA" }).click();
  await page.waitForFunction(() => [...document.querySelectorAll("button")].some((b) => b.textContent?.includes("TORCH") && !b.disabled));

  // 5. PAUSE / RESUME keep the session
  await page.getByRole("button", { name: "PAUSE", exact: true }).click();
  await acked("Pausa");
  await page.locator(".detail-title").getByText("PAUSA").waitFor();
  await page.getByRole("button", { name: "RESUME", exact: true }).click();
  await acked("Ripresa");

  // 6. Cloudflare ingest state and OBS SRT playback URL
  await page.locator(".detail-title").getByText("LIVE").waitFor();
  await page.getByRole("button", { name: "Mostra URL SRT per OBS" }).click();
  const obsUrl = await page.locator("code.secret").textContent();
  if (!obsUrl?.startsWith("srt://127.0.0.1:9710?passphrase=") || !obsUrl.includes("&streamid=play")) {
    throw new Error(`unexpected OBS URL: ${obsUrl}`);
  }
  log(`OBS URL shown (passphrase masked): ${obsUrl}`);
  await sleep(11_000); // one Cloudflare poll (CF_POLL_INTERVAL_SECONDS=10)
  await page.screenshot({ path: `${shots}/03-camera-live.png`, fullPage: true });

  // 7. STOP
  await page.getByRole("button", { name: "STOP", exact: true }).click();
  await acked("Stop stream");
  await page.screenshot({ path: `${shots}/04-camera-stopped.png`, fullPage: true });

  await writeFile(doneFile, "done\n");
  log("scenario completed, waiting for the phone to disconnect");
  await page.locator(".detail-title").getByText("OFFLINE", { exact: true }).first().waitFor({ timeout: 120_000 });
  await page.getByRole("button", { name: "← Dashboard" }).click();
  await page.getByRole("heading", { name: "Multicamera" }).waitFor();
  await page.screenshot({ path: `${shots}/05-dashboard-after.png` });
  log("OK");
} catch (err) {
  await page.screenshot({ path: `${shots}/failure.png`, fullPage: true }).catch(() => {});
  if (!existsSync(doneFile)) await writeFile(doneFile, "failed\n");
  throw err;
} finally {
  await browser.close();
}
