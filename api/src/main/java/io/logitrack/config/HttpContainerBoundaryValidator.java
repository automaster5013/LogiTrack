package io.logitrack.config;

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.util.unit.DataSize;

@Component
public class HttpContainerBoundaryValidator {
    private static final long MAX_REQUEST_HEADER_BYTES=16*1024;
    private static final long MAX_RESPONSE_HEADER_BYTES=32*1024;
    private static final long MAX_BODY_BYTES=10*1024*1024;
    private final DataSize requestHeaders;
    private final DataSize responseHeaders;
    private final DataSize formPost;
    private final DataSize swallow;

    HttpContainerBoundaryValidator(
        @Value("${server.max-http-request-header-size}") DataSize requestHeaders,
        @Value("${server.tomcat.max-http-response-header-size}") DataSize responseHeaders,
        @Value("${server.tomcat.max-http-form-post-size}") DataSize formPost,
        @Value("${server.tomcat.max-swallow-size}") DataSize swallow){
        this.requestHeaders=requestHeaders;this.responseHeaders=responseHeaders;this.formPost=formPost;this.swallow=swallow;
    }

    @PostConstruct void validate(){
        requireBounded("HTTP request header",requestHeaders,MAX_REQUEST_HEADER_BYTES);
        requireBounded("HTTP response header",responseHeaders,MAX_RESPONSE_HEADER_BYTES);
        requireBounded("HTTP form post",formPost,MAX_BODY_BYTES);
        requireBounded("HTTP swallowed body",swallow,MAX_BODY_BYTES);
    }

    private static void requireBounded(String name,DataSize value,long maximum){
        if(value.toBytes()<1||value.toBytes()>maximum)throw new IllegalStateException(name+" limit must be between 1 byte and "+maximum+" bytes");
    }
}
