package io.logitrack.config;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.*;
import java.net.URI;
import java.util.*;
@Configuration public class WebConfig implements WebMvcConfigurer {
  static final String DEFAULT_ALLOWED_ORIGINS="http://localhost:3000,http://127.0.0.1:3000";
  private final String[] allowedOrigins;
  public WebConfig(@Value("${logitrack.cors.allowed-origins:"+DEFAULT_ALLOWED_ORIGINS+"}") String allowedOrigins){
    this.allowedOrigins=parseAllowedOrigins(allowedOrigins);
    if(this.allowedOrigins.length==0)throw new IllegalArgumentException("At least one CORS allowed origin is required");
  }
  public void addCorsMappings(CorsRegistry r){r.addMapping("/api/**").allowedOrigins(allowedOrigins).allowedMethods("GET","POST","DELETE")
    .allowedHeaders("Authorization","Content-Type","Idempotency-Key",RequestTraceFilter.HEADER,"X-Operator","X-Replay-Approval","X-Discard-Approval")
    .exposedHeaders(RequestTraceFilter.HEADER).maxAge(3600);}
  static String[] parseAllowedOrigins(String configured){return Arrays.stream(configured.split(",")).map(String::trim).filter(value->!value.isEmpty()).peek(WebConfig::validateOrigin).distinct().toArray(String[]::new);}
  private static void validateOrigin(String value){
    URI origin;try{origin=URI.create(value);}catch(IllegalArgumentException error){throw new IllegalArgumentException("CORS allowed origins must be absolute HTTP(S) origins",error);}
    var scheme=origin.getScheme();var path=origin.getRawPath();
    if((!"http".equalsIgnoreCase(scheme)&&!"https".equalsIgnoreCase(scheme))||origin.getRawAuthority()==null||origin.getHost()==null||origin.getRawUserInfo()!=null||(path!=null&&!path.isEmpty())||origin.getRawQuery()!=null||origin.getRawFragment()!=null)
      throw new IllegalArgumentException("CORS allowed origins must be absolute HTTP(S) origins without paths, credentials, queries, or fragments");
  }
}
