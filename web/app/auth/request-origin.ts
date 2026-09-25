import { NextRequest } from "next/server";
import { applicationOrigin } from "./config";

export function isSameOriginMutation(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (origin) {
    try {
      return new URL(origin).origin === applicationOrigin(request.nextUrl.origin);
    } catch {
      return false;
    }
  }
  const fetchSite = request.headers.get("sec-fetch-site");
  return fetchSite === "same-origin" || fetchSite === "none";
}
