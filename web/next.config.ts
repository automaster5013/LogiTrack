import type { NextConfig } from "next";
const securityHeaders=[
  {key:"Content-Security-Policy",value:"frame-ancestors 'none'"},
  {key:"X-Content-Type-Options",value:"nosniff"},
  {key:"X-Frame-Options",value:"DENY"},
  {key:"Referrer-Policy",value:"no-referrer"},
  {key:"Permissions-Policy",value:"camera=(), microphone=(), geolocation=()"},
];
const nextConfig: NextConfig = { output: "standalone", async headers(){return [{source:"/(.*)",headers:securityHeaders}]} };
export default nextConfig;
