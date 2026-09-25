package io.logitrack.config;

import jakarta.annotation.PostConstruct;
import java.net.URI;
import java.util.Set;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class SecurityBoundaryValidator{
    private static final Set<String> LOOPBACK=Set.of("localhost","127.0.0.1","[::1]","::1");
    private final boolean enabled;
    private final String[] origins;
    SecurityBoundaryValidator(@Value("${logitrack.security.enabled:true}") boolean enabled,@Value("${logitrack.cors.allowed-origins}") String origins){
        this.enabled=enabled;this.origins=origins.split(",");
    }
    @PostConstruct void validate(){
        if(enabled)return;
        for(String value:origins){
            String host=URI.create(value.trim()).getHost();
            if(host==null||!LOOPBACK.contains(host))throw new IllegalStateException("SECURITY_ENABLED must be true when CORS allows a non-loopback origin");
        }
    }
}
