package io.logitrack.delivery;

import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController @RequestMapping("/api/deliveries")
public class DeliveryController {
    private final DeliveryService service;
    public DeliveryController(DeliveryService service){this.service=service;}
    @PostMapping
    public ResponseEntity<Delivery> create(@RequestBody CreateDeliveryRequest request,
        @RequestHeader("Idempotency-Key") String key,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId){
        var trace=traceId==null?UUID.randomUUID().toString():traceId;
        return ResponseEntity.status(HttpStatus.CREATED).header("X-Trace-Id",trace).body(service.create(request,key,trace));
    }
    @GetMapping public List<Delivery> list(@RequestParam(defaultValue="200") int limit){return service.list(validLimit(limit));}
    private int validLimit(int limit){if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");return limit;}
}
