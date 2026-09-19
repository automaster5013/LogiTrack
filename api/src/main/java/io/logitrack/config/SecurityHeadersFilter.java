package io.logitrack.config;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;

@Component @Order(Ordered.HIGHEST_PRECEDENCE)
public class SecurityHeadersFilter extends OncePerRequestFilter {
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws ServletException,IOException {
        response.setHeader("Content-Security-Policy","frame-ancestors 'none'");
        response.setHeader("X-Content-Type-Options","nosniff");
        response.setHeader("X-Frame-Options","DENY");
        response.setHeader("Referrer-Policy","no-referrer");
        response.setHeader("Permissions-Policy","camera=(), microphone=(), geolocation=()");
        if(request.getRequestURI().equals("/api")||request.getRequestURI().startsWith("/api/"))response.setHeader("Cache-Control","no-store");
        chain.doFilter(request,response);
    }
}
