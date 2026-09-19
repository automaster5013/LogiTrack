package io.logitrack.alert;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.UUID;
import org.springframework.data.domain.PageRequest;
@RestController @RequestMapping("/api/alerts")
public class AlertController {
    private final DeliveryAlertRepository repository; private final AlertService service;
    public AlertController(DeliveryAlertRepository repository,AlertService service){this.repository=repository;this.service=service;}
    @GetMapping public List<DeliveryAlert> list(@RequestParam(defaultValue="200") int limit){return repository.findAllByOrderByLastObservedAtDesc(PageRequest.of(0,validLimit(limit)));}
    @PostMapping("/{id}/acknowledgement")
    public DeliveryAlert acknowledge(@PathVariable UUID id,@RequestHeader("X-Operator") String actor,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId){return service.acknowledge(id,actor,traceId);}
    private int validLimit(int limit){if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");return limit;}
}
