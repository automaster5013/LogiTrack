package io.logitrack.stream;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;
@RestController @RequestMapping("/api/stream")
public class StreamController { private final DeliveryStream stream; public StreamController(DeliveryStream stream){this.stream=stream;}
    @GetMapping(value="/deliveries",produces=MediaType.TEXT_EVENT_STREAM_VALUE) public SseEmitter deliveries(){return stream.subscribe();}}

