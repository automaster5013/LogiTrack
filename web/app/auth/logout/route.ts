import { NextRequest, NextResponse } from "next/server";
import { applicationOrigin, authConfig, authCookie, secureCookie } from "../config";

export async function POST(request: NextRequest) {
  if (!isSameOrigin(request)) {
    return NextResponse.json(
      { error: "cross_origin_logout_rejected" },
      { status: 403, headers: { "Cache-Control": "no-store" } },
    );
  }

  let destination = new URL("/login", applicationOrigin(request.nextUrl.origin));
  try {
    const { authBase, clientId, postLogoutRedirectUri } = authConfig();
    destination = new URL(`${authBase}/logout`);
    destination.search = new URLSearchParams({ client_id: clientId, logout_uri: postLogoutRedirectUri }).toString();
  } catch {}

  const response = NextResponse.redirect(destination, 303);
  response.cookies.set(authCookie.access, "", { ...secureCookie(0, "/"), expires: new Date(0) });
  for (const name of [authCookie.state, authCookie.nonce, authCookie.verifier]) {
    response.cookies.set(name, "", { ...secureCookie(0), expires: new Date(0) });
  }
  response.headers.set("Cache-Control", "no-store");
  response.headers.set("Clear-Site-Data", '"cache", "storage"');
  return response;
}

function isSameOrigin(request: NextRequest) {
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
