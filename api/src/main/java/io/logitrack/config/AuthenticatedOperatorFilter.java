package io.logitrack.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Collections;
import java.util.Enumeration;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@ConditionalOnProperty(name="logitrack.security.enabled",havingValue="true")
public class AuthenticatedOperatorFilter extends OncePerRequestFilter{
    static final String HEADER="X-Operator";
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain)throws ServletException,IOException{
        Authentication authentication=SecurityContextHolder.getContext().getAuthentication();
        if(authentication==null||!authentication.isAuthenticated()){chain.doFilter(request,response);return;}
        String actor=authentication.getName();
        if(!isValidSubject(actor)){response.sendError(HttpServletResponse.SC_UNAUTHORIZED,"Authenticated subject is invalid");return;}
        chain.doFilter(new HttpServletRequestWrapper(request){
            @Override public String getHeader(String name){return HEADER.equalsIgnoreCase(name)?actor:super.getHeader(name);}
            @Override public Enumeration<String> getHeaders(String name){return HEADER.equalsIgnoreCase(name)?Collections.enumeration(java.util.List.of(actor)):super.getHeaders(name);}
        },response);
    }
    static boolean isValidSubject(String subject){
        if(subject==null||subject.isBlank()||subject.length()>120||subject.codePoints().anyMatch(Character::isISOControl))return false;
        int first=subject.codePointAt(0),last=subject.codePointBefore(subject.length());
        return !isBoundaryWhitespace(first)&&!isBoundaryWhitespace(last);
    }
    private static boolean isBoundaryWhitespace(int value){return Character.isWhitespace(value)||Character.isSpaceChar(value)||value==0xfeff;}
}
