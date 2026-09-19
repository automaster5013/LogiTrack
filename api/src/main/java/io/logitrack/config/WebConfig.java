package io.logitrack.config;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.*;
import java.util.*;
@Configuration public class WebConfig implements WebMvcConfigurer {
  private final String[] allowedOrigins;
  public WebConfig(@Value("${logitrack.cors.allowed-origins:http://localhost:3000}") String allowedOrigins){
    this.allowedOrigins=Arrays.stream(allowedOrigins.split(",")).map(String::trim).filter(value->!value.isEmpty()).distinct().toArray(String[]::new);
    if(this.allowedOrigins.length==0)throw new IllegalArgumentException("At least one CORS allowed origin is required");
  }
  public void addCorsMappings(CorsRegistry r){r.addMapping("/api/**").allowedOrigins(allowedOrigins).allowedMethods("GET","POST","DELETE")
    .allowedHeaders("Content-Type","Idempotency-Key",RequestTraceFilter.HEADER,"X-Operator","X-Replay-Approval")
    .exposedHeaders(RequestTraceFilter.HEADER).maxAge(3600);}
}
