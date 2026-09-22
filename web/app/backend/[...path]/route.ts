import { NextRequest,NextResponse } from "next/server";
import { authCookie } from "../../auth/config";

const allowedRequestHeaders=["accept","content-type","idempotency-key","x-trace-id","x-replay-approval","x-discard-approval"];
export async function GET(request:NextRequest,context:{params:Promise<{path:string[]}>}){return proxy(request,context)}
export async function POST(request:NextRequest,context:{params:Promise<{path:string[]}>}){return proxy(request,context)}
export async function DELETE(request:NextRequest,context:{params:Promise<{path:string[]}>}){return proxy(request,context)}
async function proxy(request:NextRequest,{params}:{params:Promise<{path:string[]}>}){
 const token=request.cookies.get(authCookie.access)?.value;if(!token)return NextResponse.json({error:"authentication_required"},{status:401,headers:{"Cache-Control":"no-store"}});
 const path=(await params).path;if(!path.length||path[0]!=="api"||path.some(part=>part===".."||part.includes("/")))return NextResponse.json({error:"invalid_proxy_path"},{status:400});
 const upstreamBase=(process.env.INTERNAL_API_URL||process.env.API_INTERNAL_URL||"http://api:8080").replace(/\/$/,"");
 const url=new URL(`${upstreamBase}/${path.map(encodeURIComponent).join("/")}`);url.search=request.nextUrl.search;
 const headers=new Headers({Authorization:`Bearer ${token}`});for(const name of allowedRequestHeaders){const value=request.headers.get(name);if(value)headers.set(name,value)}
 const body=request.method==="GET"?undefined:await request.arrayBuffer();
 const upstream=await fetch(url,{method:request.method,headers,body,redirect:"manual",cache:"no-store"});
 const responseHeaders=new Headers({"Cache-Control":"no-store"});for(const name of ["content-type","content-disposition","x-trace-id"]){const value=upstream.headers.get(name);if(value)responseHeaders.set(name,value)}
 return new Response(upstream.body,{status:upstream.status,headers:responseHeaders});
}
