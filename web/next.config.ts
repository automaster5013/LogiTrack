import type { NextConfig } from "next";
const securityHeaders=[
  {key:"Cross-Origin-Opener-Policy",value:"same-origin"},
  {key:"Cross-Origin-Resource-Policy",value:"same-origin"},
  {key:"Origin-Agent-Cluster",value:"?1"},
  {key:"X-Permitted-Cross-Domain-Policies",value:"none"},
  {key:"X-Content-Type-Options",value:"nosniff"},
  {key:"X-Frame-Options",value:"DENY"},
  {key:"Referrer-Policy",value:"no-referrer"},
  {key:"Permissions-Policy",value:"camera=(), microphone=(), geolocation=()"},
];
const nextConfig: NextConfig = { output: "standalone", poweredByHeader: false, async headers(){return [{source:"/(.*)",headers:securityHeaders}]} };
export default nextConfig;
