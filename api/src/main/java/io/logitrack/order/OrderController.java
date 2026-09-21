package io.logitrack.order;

import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/orders")
public class OrderController {
    private final OrderService service;
    public OrderController(OrderService service){this.service=service;}

    @PostMapping
    public ResponseEntity<OrderSummary> create(@RequestBody CreateOrderRequest request,
        @RequestHeader("Idempotency-Key") String key,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId) {
        var trace=traceId==null?UUID.randomUUID().toString():traceId;
        return ResponseEntity.status(HttpStatus.CREATED).header("X-Trace-Id",trace).body(service.create(request,key,trace));
    }

    @GetMapping
    public List<OrderSummary> list(@RequestParam(defaultValue="200") int limit){return service.list(validLimit(limit));}

    @GetMapping("/page")
    public OrderService.OrderPage page(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){
        if(page<0)throw new IllegalArgumentException("page must be zero or greater");
        return service.page(page,validLimit(size));
    }

    @PostMapping("/{id}/dispatch")
    public OrderSummary dispatch(@PathVariable UUID id, @RequestBody DispatchOrderRequest request,
        @RequestHeader("Idempotency-Key") String key,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId) {
        return service.dispatch(id,request,key,traceId==null?UUID.randomUUID().toString():traceId);
    }
    private int validLimit(int limit){if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");return limit;}
}
