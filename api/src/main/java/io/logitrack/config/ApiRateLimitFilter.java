package io.logitrack.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Clock;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicReference;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;

public class ApiRateLimitFilter extends OncePerRequestFilter {
    static final String LIMIT_HEADER="RateLimit-Limit";
    static final String REMAINING_HEADER="RateLimit-Remaining";
    static final String RESET_HEADER="RateLimit-Reset";
    private static final String OVERFLOW_KEY="overflow";
    private final int limit;
    private final long windowSeconds;
    private final int maxSubjects;
    private final Clock clock;
    private final ConcurrentHashMap<String,Window> windows=new ConcurrentHashMap<>();

    public ApiRateLimitFilter(int limit,long windowSeconds,int maxSubjects){
        this(limit,windowSeconds,maxSubjects,Clock.systemUTC());
    }

    ApiRateLimitFilter(int limit,long windowSeconds,int maxSubjects,Clock clock){
        if(limit<1||windowSeconds<1||maxSubjects<1)throw new IllegalArgumentException("API rate limit settings must be positive");
        this.limit=limit;this.windowSeconds=windowSeconds;this.maxSubjects=maxSubjects;this.clock=clock;
    }

    @Override protected boolean shouldNotFilter(HttpServletRequest request){return !request.getRequestURI().startsWith("/api/");}

    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)throws ServletException,IOException{
        long now=clock.instant().getEpochSecond();
        String key=subjectKey(request,now);
        AtomicReference<Decision> result=new AtomicReference<>();
        windows.compute(key,(ignored,current)->{
            Window active=current==null||current.expiresAt<=now?new Window(0,windowEnd(now)):current;
            int used=active.used+1;
            result.set(new Decision(used<=limit,Math.max(0,limit-used),active.expiresAt));
            return new Window(used,active.expiresAt);
        });
        Decision decision=result.get();
        long retryAfter=Math.max(1,decision.resetAt-now);
        response.setHeader(LIMIT_HEADER,Integer.toString(limit));
        response.setHeader(REMAINING_HEADER,Integer.toString(decision.remaining));
        response.setHeader(RESET_HEADER,Long.toString(retryAfter));
        if(!decision.allowed){
            response.setHeader("Retry-After",Long.toString(retryAfter));
            response.setStatus(429);response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"API request rate limit exceeded\"}");return;
        }
        chain.doFilter(request,response);
    }

    private String subjectKey(HttpServletRequest request,long now){
        Authentication authentication=SecurityContextHolder.getContext().getAuthentication();
        String key=authentication!=null&&authentication.isAuthenticated()?"subject:"+authentication.getName():"address:"+request.getRemoteAddr();
        if(windows.containsKey(key))return key;
        if(windows.size()<maxSubjects)return key;
        windows.entrySet().removeIf(entry->entry.getValue().expiresAt<=now);
        return windows.size()<maxSubjects?key:OVERFLOW_KEY;
    }

    private long windowEnd(long now){return Math.addExact(now-(now%windowSeconds),windowSeconds);}
    private record Window(int used,long expiresAt){}
    private record Decision(boolean allowed,int remaining,long resetAt){}
}
