package io.logitrack.outbox;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/operations/outbox")
public class OutboxRecoveryController {
    private final OutboxRecoveryService service;
    public OutboxRecoveryController(OutboxRecoveryService service){this.service=service;}
    @GetMapping("/failures") public List<OutboxRecoveryService.FailureView> failures(){return service.failures();}
    @GetMapping("/retry-audits") public List<OutboxRetryAudit> audits(){return service.audits();}
    @PostMapping("/failures/{id}/retry") public OutboxRecoveryService.FailureView retry(@PathVariable UUID id,@RequestHeader("X-Operator") String actor){return service.retry(id,actor);}
}
