function sourceOrigin(value:string,name:string,allowRelative=false){
  if(allowRelative&&value.startsWith("/")&&!value.startsWith("//"))return undefined;
  const url=new URL(value);
  if((url.protocol!=="http:"&&url.protocol!=="https:")||url.username||url.password)throw new Error(`${name} must be an HTTP(S) URL without credentials`);
  return url.origin;
}

const apiOrigin=sourceOrigin(process.env.NEXT_PUBLIC_API_URL||"http://localhost:8080","NEXT_PUBLIC_API_URL",true);
const mapOrigin=sourceOrigin(process.env.NEXT_PUBLIC_MAP_STYLE_URL||"https://tiles.openfreemap.org/styles/liberty","NEXT_PUBLIC_MAP_STYLE_URL")!;
const connectSources=["'self'",apiOrigin,mapOrigin].filter((value,index,values):value is string=>Boolean(value)&&values.indexOf(value)===index).join(" ");

export function contentSecurityPolicy(nonce:string){
  if(!/^[A-Za-z0-9+/=]+$/.test(nonce))throw new Error("CSP nonce is invalid");
  const scriptSources=process.env.NODE_ENV==="development"?`script-src 'self' 'nonce-${nonce}' 'strict-dynamic' 'unsafe-eval'`:`script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`;
  return [
    "default-src 'self'",
    "base-uri 'self'",
    `connect-src ${connectSources}`,
    "font-src 'self' data:",
    "form-action 'self'",
    "frame-ancestors 'none'",
    "frame-src 'none'",
    `img-src 'self' data: blob: ${mapOrigin}`,
    "media-src 'none'",
    "object-src 'none'",
    scriptSources,
    "style-src 'self' 'unsafe-inline'",
    "worker-src 'self' blob:",
  ].join("; ");
}
