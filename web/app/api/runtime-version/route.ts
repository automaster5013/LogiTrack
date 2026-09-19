import { randomUUID } from "node:crypto";

export const dynamic = "force-dynamic";

const runtimeVersion = randomUUID();

export function GET() {
  return Response.json(
    { version: runtimeVersion },
    { headers: { "Cache-Control": "no-store, no-cache, must-revalidate" } },
  );
}
