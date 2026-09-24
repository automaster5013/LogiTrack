import { NextRequest, NextResponse } from "next/server";
import { verifyAccessToken } from "../../auth/access-token";
import { applicationOrigin, authCookie, secureCookie } from "../../auth/config";

const allowedRequestHeaders = ["accept", "content-type", "idempotency-key", "x-trace-id", "x-replay-approval", "x-discard-approval"];
const maxRequestBodyBytes = 1024 * 1024;
const upstreamTimeoutMs = 15_000;

export async function GET(request: NextRequest, context: { params: Promise<{ path: string[] }> }) { return proxy(request, context); }
export async function POST(request: NextRequest, context: { params: Promise<{ path: string[] }> }) { return proxy(request, context); }
export async function DELETE(request: NextRequest, context: { params: Promise<{ path: string[] }> }) { return proxy(request, context); }

async function proxy(request: NextRequest, { params }: { params: Promise<{ path: string[] }> }) {
  if (request.method !== "GET" && !isSameOriginMutation(request)) {
    return jsonError("cross_origin_request_rejected", 403);
  }

  const token = request.cookies.get(authCookie.access)?.value;
  if (!token) return jsonError("authentication_required", 401);
  try {
    await verifyAccessToken(token);
  } catch {
    const response = jsonError("authentication_required", 401);
    response.cookies.set(authCookie.access, "", { ...secureCookie(0, "/"), expires: new Date(0) });
    return response;
  }

  const path = (await params).path;
  if (!path.length || path[0] !== "api" || path.some(part => !part || part === "." || part === ".." || part.includes("/"))) {
    return jsonError("invalid_proxy_path", 400);
  }

  const declaredLength = request.headers.get("content-length");
  if (declaredLength && (!/^\d+$/.test(declaredLength) || Number(declaredLength) > maxRequestBodyBytes)) {
    return jsonError("request_body_too_large", 413);
  }
  let body: ArrayBuffer | undefined;
  try {
    body = await readBoundedBody(request);
  } catch (error) {
    return error instanceof RequestBodyTooLarge ? jsonError("request_body_too_large", 413) : jsonError("invalid_request_body", 400);
  }

  const upstreamBase = (process.env.INTERNAL_API_URL || process.env.API_INTERNAL_URL || "http://api:8080").replace(/\/$/, "");
  const url = new URL(`${upstreamBase}/${path.map(encodeURIComponent).join("/")}`);
  url.search = request.nextUrl.search;
  const headers = new Headers({ Authorization: `Bearer ${token}` });
  for (const name of allowedRequestHeaders) {
    const value = request.headers.get(name);
    if (value) headers.set(name, value);
  }

  try {
    const upstream = await fetch(url, {
      method: request.method,
      headers,
      body,
      redirect: "manual",
      cache: "no-store",
      signal: AbortSignal.timeout(upstreamTimeoutMs),
    });
    const responseHeaders = new Headers({ "Cache-Control": "no-store" });
    for (const name of ["content-type", "content-disposition", "x-trace-id"]) {
      const value = upstream.headers.get(name);
      if (value) responseHeaders.set(name, value);
    }
    return new Response(upstream.body, { status: upstream.status, headers: responseHeaders });
  } catch {
    return jsonError("upstream_unavailable", 502);
  }
}

function isSameOriginMutation(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (origin) {
    try {
      return new URL(origin).origin === applicationOrigin(request.nextUrl.origin);
    } catch {
      return false;
    }
  }
  const fetchSite = request.headers.get("sec-fetch-site");
  return fetchSite === null || fetchSite === "same-origin" || fetchSite === "none";
}

function jsonError(error: string, status: number) {
  return NextResponse.json({ error }, { status, headers: { "Cache-Control": "no-store" } });
}

class RequestBodyTooLarge extends Error {}

async function readBoundedBody(request: NextRequest) {
  if (request.method === "GET" || !request.body) return undefined;
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxRequestBodyBytes) {
      await reader.cancel();
      throw new RequestBodyTooLarge();
    }
    chunks.push(value);
  }
  const body = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body.buffer;
}
