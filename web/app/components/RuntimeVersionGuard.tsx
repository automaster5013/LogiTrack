"use client";

import { useEffect, useState } from "react";

const CHECK_INTERVAL_MS = 15_000;

export default function RuntimeVersionGuard() {
  const [runtime,setRuntime]=useState<{revision:string;builtAt:string;environment:string}|null>(null);
  const [detailsOpen,setDetailsOpen]=useState(false);
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

  useEffect(() => {
    if (!detailsOpen) return;
    const closeOnEscape = (event: KeyboardEvent) => { if (event.key === "Escape") setDetailsOpen(false); };
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [detailsOpen]);

  if (!runtime) return null;
  const shortRevision=runtime.revision.match(/^[0-9a-f]{40}$/)?.[0].slice(0,7)||runtime.revision;
  const builtAt=new Date(runtime.builtAt);
  const builtLabel=Number.isNaN(builtAt.getTime())?runtime.builtAt:builtAt.toLocaleString("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",second:"2-digit"});
  const environmentLabel=({local:"LOCAL",staging:"STAGING",production:"PROD",ci:"CI",test:"TEST"} as Record<string,string>)[runtime.environment]||runtime.environment.toUpperCase();
  return <div className="runtimeMeta" data-environment={runtime.environment}>
    {detailsOpen&&<aside className="runtimeDetails" id="runtime-details" aria-label="실행 환경 상세">
      <header><strong>실행 환경 상세</strong><button type="button" onClick={()=>setDetailsOpen(false)} aria-label="실행 환경 상세 닫기">×</button></header>
      <dl><div><dt>환경</dt><dd>{environmentLabel}</dd></div><div><dt>Git 커밋</dt><dd><code>{runtime.revision}</code></dd></div><div><dt>빌드 시각</dt><dd><time dateTime={runtime.builtAt}>{builtLabel}</time></dd></div></dl>
      <p>커밋이 같으면 실행 코드는 같습니다. 화면의 주문·차량 수치는 환경별 데이터에 따라 다를 수 있습니다.</p>
    </aside>}
    <button type="button" className="runtimeBadge" aria-label={`실행 환경 ${environmentLabel} 버전 ${shortRevision}`} aria-expanded={detailsOpen} aria-controls="runtime-details" title="실행 환경 상세 보기" onClick={()=>setDetailsOpen(open=>!open)}><i aria-hidden="true"/><span>{environmentLabel}</span><code>{shortRevision}</code></button>
  </div>;
}
