package io.logitrack.alert;
import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.UUID;
@RestController @RequestMapping("/api/alerts")
public class AlertController {
    private final DeliveryAlertRepository repository; private final AlertService service;
    public AlertController(DeliveryAlertRepository repository,AlertService service){this.repository=repository;this.service=service;}
    @GetMapping public List<DeliveryAlert> list(){return repository.findAllByOrderByLastObservedAtDesc();}
    @PostMapping("/{id}/acknowledgement")
    public DeliveryAlert acknowledge(@PathVariable UUID id,@RequestHeader("X-Operator") String actor,
        @RequestHeader(value="X-Trace-Id",required=false) String traceId){return service.acknowledge(id,actor,traceId);}
}
