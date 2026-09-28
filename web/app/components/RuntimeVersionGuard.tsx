"use client";

import { useEffect, useState } from "react";

const CHECK_INTERVAL_MS = 15_000;

export default function RuntimeVersionGuard() {
  const [runtime,setRuntime]=useState<{revision:string;builtAt:string;environment:string}|null>(null);
  useEffect(() => {
    let active = true;
    let checking = false;
    let timer: number | undefined;
    let currentVersion: string | undefined;

    async function checkVersion() {
      if (!active || checking) return;
      checking = true;
      try {
        const response = await fetch("/api/runtime-version", { cache: "no-store" });
        if (!response.ok) return;
        const result = await response.json() as { version?: string; revision?: string; builtAt?: string; environment?: string };
        if (!active || !result.version) return;
        if (currentVersion && currentVersion !== result.version) {
          window.location.reload();
          return;
        }
        currentVersion = result.version;
        if (result.revision && result.builtAt && result.environment) setRuntime(current=>current&&current.revision===result.revision&&current.builtAt===result.builtAt&&current.environment===result.environment?current:{revision:result.revision!,builtAt:result.builtAt!,environment:result.environment!});
      } catch {
        // A deployment may briefly interrupt the request. The next poll retries.
      } finally {
        checking = false;
      }
    }

    async function poll() {
      await checkVersion();
      if (active) timer = window.setTimeout(poll, CHECK_INTERVAL_MS);
    }
    void poll();
    const onVisible = () => { if (document.visibilityState === "visible") void checkVersion(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      active = false;
      if (timer !== undefined) window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, []);

  if (!runtime) return null;
  const shortRevision=runtime.revision.match(/^[0-9a-f]{40}$/)?.[0].slice(0,7)||runtime.revision;
  const builtAt=new Date(runtime.builtAt);
  const builtLabel=Number.isNaN(builtAt.getTime())?runtime.builtAt:builtAt.toLocaleString("ko-KR",{timeZone:"Asia/Seoul",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit"});
  const environmentLabel=({local:"LOCAL",staging:"STAGING",production:"PROD",ci:"CI",test:"TEST"} as Record<string,string>)[runtime.environment]||runtime.environment.toUpperCase();
  return <aside className="runtimeBadge" data-environment={runtime.environment} aria-label={`실행 환경 ${environmentLabel} 버전 ${shortRevision}`} title={`환경 ${runtime.environment} · Git ${runtime.revision} · 빌드 ${builtLabel}`}><i aria-hidden="true"/><span>{environmentLabel}</span><code>{shortRevision}</code></aside>;
}
