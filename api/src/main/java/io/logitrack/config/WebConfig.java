package io.logitrack.config;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.*;
@Configuration public class WebConfig implements WebMvcConfigurer {
  public void addCorsMappings(CorsRegistry r){r.addMapping("/api/**").allowedOrigins("http://localhost:3000").allowedMethods("GET","POST","DELETE").allowedHeaders("*");}
}
