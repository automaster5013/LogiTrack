package io.logitrack.alert;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.*;
@RestController @RequestMapping("/api/alerts")
public class AlertController {
    private final DeliveryAlertRepository repository; private final AlertService service;
    public AlertController(DeliveryAlertRepository repository,AlertService service){this.repository=repository;this.service=service;}
    @GetMapping public List<DeliveryAlert> list(@RequestParam(defaultValue="200") int limit){return repository.findAllByOrderByLastObservedAtDesc(PageRequest.of(0,validLimit(limit)));}
    @GetMapping("/page") public AlertPage page(@RequestParam(defaultValue="0") int page,
        @RequestParam(defaultValue="100") int size){
        if(page<0)throw new IllegalArgumentException("page must be zero or greater");
        var result=repository.findAll(PageRequest.of(page,validLimit(size),Sort.by(Sort.Direction.DESC,"lastObservedAt").and(Sort.by(Sort.Direction.DESC,"id"))));
        return new AlertPage(result.getContent(),result.getNumber(),result.getSize(),result.getTotalElements(),result.hasNext());
    }
    @PostMapping("/{id}/acknowledgement")
    public DeliveryAlert acknowledge(@PathVariable UUID id,@RequestHeader("X-Operator") String actor,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId){return service.acknowledge(id,actor,traceId);}
    private int validLimit(int limit){if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");return limit;}
    public record AlertPage(List<DeliveryAlert> items,int page,int size,long totalElements,boolean hasMore){}
}
