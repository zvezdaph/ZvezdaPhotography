import { useEffect, useRef, useState } from "preact/hooks";
import { RemoteTrack, Room, RoomEvent, Track } from "livekit-client";
import type { RemoteParticipant, RemoteTrackPublication } from "livekit-client";

import { api, ApiError } from "../api";

type PreviewState = "connecting" | "ready" | "waiting" | "error";

export function RealtimePreview(props: { cameraId: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const roomRef = useRef<Room | null>(null);
  const trackRef = useRef<RemoteTrack | null>(null);
  const [state, setState] = useState<PreviewState>("connecting");
  const [message, setMessage] = useState("Connessione anteprima realtime…");

  useEffect(() => {
    let cancelled = false;
    const room = new Room({ adaptiveStream: true, dynacast: true });
    roomRef.current = room;

    const detach = () => {
      const track = trackRef.current;
      const element = videoRef.current;
      if (track && element) track.detach(element);
      trackRef.current = null;
    };

    const attach = (track: RemoteTrack) => {
      if (track.kind !== Track.Kind.Video) return;
      const element = videoRef.current;
      if (!element) return;
      detach();
      trackRef.current = track;
      track.attach(element);
      element.autoplay = true;
      element.muted = true;
      element.playsInline = true;
      void element.play().catch(() => undefined);
      setState("ready");
      setMessage("Anteprima realtime");
    };

    const onTrackSubscribed = (
      track: RemoteTrack,
      _publication: RemoteTrackPublication,
      _participant: RemoteParticipant,
    ) => attach(track);

    const onTrackUnsubscribed = (track: RemoteTrack) => {
      if (trackRef.current === track) {
        detach();
        setState("waiting");
        setMessage("Camera collegata, in attesa del video…");
      }
    };

    room.on(RoomEvent.TrackSubscribed, onTrackSubscribed);
    room.on(RoomEvent.TrackUnsubscribed, onTrackUnsubscribed);
    room.on(RoomEvent.Reconnecting, () => {
      if (!cancelled) {
        setState("connecting");
        setMessage("Riconnessione anteprima…");
      }
    });
    room.on(RoomEvent.Disconnected, () => {
      if (!cancelled) {
        setState("waiting");
        setMessage("Anteprima disconnessa");
      }
    });

    void (async () => {
      try {
        const credentials = await api.realtimePreview(props.cameraId);
        if (cancelled) return;
        await room.connect(credentials.serverUrl, credentials.participantToken);
        if (cancelled) return;

        setState("waiting");
        setMessage("Camera collegata, in attesa del video…");

        // TrackSubscribed is not emitted for publications already present when
        // the subscriber joins, so inspect the room once after connect.
        for (const participant of room.remoteParticipants.values()) {
          const publication = participant.getTrackPublication(Track.Source.Camera);
          const track = publication?.videoTrack;
          if (track) {
            attach(track);
            break;
          }
        }
      } catch (error) {
        if (cancelled) return;
        setState("error");
        setMessage(error instanceof ApiError ? error.message : "Anteprima realtime non disponibile");
      }
    })();

    return () => {
      cancelled = true;
      detach();
      room.removeAllListeners();
      void room.disconnect();
      roomRef.current = null;
    };
  }, [props.cameraId]);

  return (
    <div class="realtime-preview">
      <video ref={videoRef} class="realtime-video" autoplay muted playsInline />
      {state !== "ready" ? (
        <div class={`realtime-overlay realtime-${state}`}>
          {state === "connecting" ? <span class="spinner" aria-hidden="true" /> : null}
          <span>{message}</span>
        </div>
      ) : (
        <span class="preview-mode-badge">WEBRTC · PRE-LIVE</span>
      )}
    </div>
  );
}
