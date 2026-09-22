import { createHash, randomBytes } from "node:crypto";

export const authCookie={state:"lt_oauth_state",verifier:"lt_pkce_verifier",nonce:"lt_oidc_nonce",access:"lt_access_token"} as const;
export function authConfig(){
 const authBase=required("COGNITO_AUTHORIZATION_BASE_URL").replace(/\/$/,"");
 const issuer=required("COGNITO_ISSUER_URI").replace(/\/$/,"");
 return {authBase,issuer,clientId:required("COGNITO_CLIENT_ID"),redirectUri:required("OIDC_REDIRECT_URI"),postLogoutRedirectUri:required("OIDC_POST_LOGOUT_REDIRECT_URI")};
}
export function randomUrlSafe(bytes=32){return randomBytes(bytes).toString("base64url")}
export function sha256UrlSafe(value:string){return createHash("sha256").update(value).digest("base64url")}
export function secureCookie(maxAge:number,path="/auth"){
 return {httpOnly:true,secure:process.env.NODE_ENV==="production",sameSite:"lax" as const,path,maxAge};
}
function required(name:string){const value=process.env[name]?.trim();if(!value)throw new Error(`${name} is required for operator authentication`);return value}
