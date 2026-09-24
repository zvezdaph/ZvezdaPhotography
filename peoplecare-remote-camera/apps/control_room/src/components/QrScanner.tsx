import { useEffect, useRef, useState } from "preact/hooks";
import { parsePairingQr } from "@protocol";

/**
 * Reads the pairing QR code shown by the phone with the PC webcam.
 * Decoding runs locally in the browser (jsQR); nothing is uploaded.
 */
export function QrScanner(props: { onCode: (code: string) => void; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let stream: MediaStream | null = null;
    let frame = 0;
    let stopped = false;
    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError("Webcam non disponibile in questo browser");
        return;
      }
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment", width: { ideal: 1280 } }, audio: false });
      } catch {
        setError("Accesso alla webcam negato o non disponibile");
        return;
      }
      // jsQR is loaded on demand to keep the main bundle small.
      const { default: jsQR } = await import("jsqr");
      const video = videoRef.current;
      if (!video || stopped) return;
      video.srcObject = stream;
      await video.play().catch(() => undefined);
      const tick = () => {
        if (stopped) return;
        const canvas = canvasRef.current;
        if (canvas && video.readyState >= 2 && video.videoWidth > 0) {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          const ctx = canvas.getContext("2d", { willReadFrequently: true });
          if (ctx) {
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const image = ctx.getImageData(0, 0, canvas.width, canvas.height);
            const result = jsQR(image.data, image.width, image.height, { inversionAttempts: "dontInvert" });
            const code = result ? parsePairingQr(result.data) : null;
            if (code) {
              props.onCode(code);
              return;
            }
          }
        }
        frame = requestAnimationFrame(tick);
      };
      frame = requestAnimationFrame(tick);
    }
    void start();
    return () => {
      stopped = true;
      cancelAnimationFrame(frame);
      stream?.getTracks().forEach((t) => t.stop());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div class="qr-scanner">
      {error ? <p class="notice notice-error">{error}</p> : <video ref={videoRef} muted playsInline class="qr-video" />}
      <canvas ref={canvasRef} hidden />
      <p class="hint">Inquadra il QR mostrato dal telefono nella schermata «Associa alla regia».</p>
      <button type="button" class="btn btn-ghost" onClick={props.onClose}>
        Annulla scansione
      </button>
    </div>
  );
}
