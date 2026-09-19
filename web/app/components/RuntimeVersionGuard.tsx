"use client";

import { useEffect } from "react";

const CHECK_INTERVAL_MS = 15_000;

export default function RuntimeVersionGuard() {
  useEffect(() => {
    let active = true;
    let currentVersion: string | undefined;

    async function checkVersion() {
      try {
        const response = await fetch("/api/runtime-version", { cache: "no-store" });
        if (!response.ok) return;
        const result = await response.json() as { version?: string };
        if (!active || !result.version) return;
        if (currentVersion && currentVersion !== result.version) {
          window.location.reload();
          return;
        }
        currentVersion = result.version;
      } catch {
        // A deployment may briefly interrupt the request. The next poll retries.
      }
    }

    void checkVersion();
    const interval = window.setInterval(checkVersion, CHECK_INTERVAL_MS);
    const onVisible = () => { if (document.visibilityState === "visible") void checkVersion(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      active = false;
      window.clearInterval(interval);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  return null;
}
