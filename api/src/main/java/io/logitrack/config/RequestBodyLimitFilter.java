package io.logitrack.config;

import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.util.unit.DataSize;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.*;
import java.nio.charset.StandardCharsets;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE+20)
public class RequestBodyLimitFilter extends OncePerRequestFilter {
    private final long maxBytes;
    public RequestBodyLimitFilter(@Value("${logitrack.http.max-request-body-size:1MB}") DataSize maxSize){maxBytes=maxSize.toBytes();if(maxBytes<1)throw new IllegalArgumentException("HTTP request body limit must be positive");}
    @Override protected void doFilterInternal(HttpServletRequest request,HttpServletResponse response,FilterChain chain) throws ServletException,IOException {
        if(request.getMethod().matches("POST|PUT|PATCH"))chain.doFilter(new LimitedRequest(request,maxBytes),response);else chain.doFilter(request,response);
    }
    static final class LimitedRequest extends HttpServletRequestWrapper {
        private final long maxBytes;private ServletInputStream input;
        LimitedRequest(HttpServletRequest request,long maxBytes){super(request);this.maxBytes=maxBytes;}
        @Override public ServletInputStream getInputStream() throws IOException {if(input==null)input=new LimitedInputStream(super.getInputStream(),maxBytes);return input;}
        @Override public BufferedReader getReader() throws IOException {return new BufferedReader(new InputStreamReader(getInputStream(),getCharacterEncoding()==null?StandardCharsets.UTF_8:java.nio.charset.Charset.forName(getCharacterEncoding())));}
    }
    static final class LimitedInputStream extends ServletInputStream {
        private final ServletInputStream delegate;private final long maxBytes;private long read;
        LimitedInputStream(ServletInputStream delegate,long maxBytes){this.delegate=delegate;this.maxBytes=maxBytes;}
        @Override public int read() throws IOException {var value=delegate.read();if(value>=0&&++read>maxBytes)throw new RequestBodyTooLargeException();return value;}
        @Override public int read(byte[] bytes,int offset,int length) throws IOException {var count=delegate.read(bytes,offset,length);if(count>0&&(read+=count)>maxBytes)throw new RequestBodyTooLargeException();return count;}
        @Override public boolean isFinished(){return delegate.isFinished();}
        @Override public boolean isReady(){return delegate.isReady();}
        @Override public void setReadListener(ReadListener listener){delegate.setReadListener(listener);}
    }
    public static final class RequestBodyTooLargeException extends IOException {RequestBodyTooLargeException(){super("Request body exceeds configured limit");}}
}
