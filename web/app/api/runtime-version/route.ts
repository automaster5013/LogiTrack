import { randomUUID } from "node:crypto";

export const dynamic = "force-dynamic";

const runtimeVersion = randomUUID();
const revision = process.env.APP_REVISION || "local";
const builtAt = process.env.APP_BUILD_TIME || "unknown";

export function GET() {
  return Response.json(
    { version: runtimeVersion, revision, builtAt },
    { headers: { "Cache-Control": "no-store, no-cache, must-revalidate" } },
  );
}
