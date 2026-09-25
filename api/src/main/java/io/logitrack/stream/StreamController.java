package io.logitrack.stream;
import jakarta.servlet.http.HttpServletRequest;
import java.security.Principal;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
@RestController @RequestMapping("/api/stream")
public class StreamController { private final DeliveryStream stream; public StreamController(DeliveryStream stream){this.stream=stream;}
    @GetMapping(value="/deliveries",produces=MediaType.TEXT_EVENT_STREAM_VALUE) public SseEmitter deliveries(Principal principal,HttpServletRequest request){
        String key=principal==null?"address:"+request.getRemoteAddr():"subject:"+principal.getName();return stream.subscribe(key);
    }}

