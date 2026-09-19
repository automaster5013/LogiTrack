export class ApiRequestError extends Error {
  constructor(public status:number,public traceId?:string,message="API request failed"){super(message);this.name="ApiRequestError"}
}

export async function fetchJson<T>(url:string,init?:RequestInit):Promise<T>{
  const response=await fetch(url,init);
  if(!response.ok){
    let message=`API request failed with HTTP ${response.status}`;
    try{const detail=await response.json() as {error?:string};if(detail.error)message=detail.error}catch{}
    throw new ApiRequestError(response.status,response.headers.get("X-Trace-Id")||undefined,message);
  }
  return response.json() as Promise<T>;
}
