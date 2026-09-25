import type { NextConfig } from "next";
const scriptSources=process.env.NODE_ENV==="development"?"script-src 'self' 'unsafe-inline' 'unsafe-eval'":"script-src 'self' 'unsafe-inline'";
const contentSecurityPolicy=[
  "default-src 'self'",
  "base-uri 'self'",
  "connect-src 'self' http://localhost:8080 http://127.0.0.1:8080 https://tiles.openfreemap.org",
  "font-src 'self' data:",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "frame-src 'none'",
  "img-src 'self' data: blob: https://tiles.openfreemap.org",
  "media-src 'none'",
  "object-src 'none'",
  scriptSources,
  "style-src 'self' 'unsafe-inline'",
  "worker-src 'self' blob:",
].join("; ");
const securityHeaders=[
  {key:"Content-Security-Policy",value:contentSecurityPolicy},
  {key:"X-Content-Type-Options",value:"nosniff"},
  {key:"X-Frame-Options",value:"DENY"},
  {key:"Referrer-Policy",value:"no-referrer"},
  {key:"Permissions-Policy",value:"camera=(), microphone=(), geolocation=()"},
];
const nextConfig: NextConfig = { output: "standalone", poweredByHeader: false, async headers(){return [{source:"/(.*)",headers:securityHeaders}]} };
export default nextConfig;
