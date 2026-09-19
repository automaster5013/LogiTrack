package io.logitrack.config;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.*;
import java.util.regex.Pattern;

@Component @Order(Ordered.HIGHEST_PRECEDENCE+10)
public class RequestTraceFilter extends OncePerRequestFilter {
    public static final String HEADER="X-Trace-Id";
    private static final Pattern SAFE=Pattern.compile("[A-Za-z0-9._:-]{1,128}");
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws ServletException,IOException {
        var supplied=request.getHeader(HEADER);
        if(supplied!=null&&!SAFE.matcher(supplied).matches()){
            response.setStatus(HttpServletResponse.SC_BAD_REQUEST);response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"X-Trace-Id must contain 1-128 safe characters\"}");return;
        }
        var traceId=supplied==null?UUID.randomUUID().toString():supplied;
        response.setHeader(HEADER,traceId);MDC.put("requestId",traceId);
        try{chain.doFilter(new TraceRequest(request,traceId),response);}finally{MDC.remove("requestId");}
    }
    private static class TraceRequest extends HttpServletRequestWrapper {
        private final String traceId;
        TraceRequest(HttpServletRequest request,String traceId){super(request);this.traceId=traceId;}
        @Override public String getHeader(String name){return HEADER.equalsIgnoreCase(name)?traceId:super.getHeader(name);}
        @Override public Enumeration<String> getHeaders(String name){return HEADER.equalsIgnoreCase(name)?Collections.enumeration(List.of(traceId)):super.getHeaders(name);}
        @Override public Enumeration<String> getHeaderNames(){var names=Collections.list(super.getHeaderNames());if(names.stream().noneMatch(HEADER::equalsIgnoreCase))names.add(HEADER);return Collections.enumeration(names);}
    }
}
