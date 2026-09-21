package io.logitrack.outbox;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/operations/outbox")
public class OutboxRecoveryController {
    private final OutboxRecoveryService service;
    public OutboxRecoveryController(OutboxRecoveryService service){this.service=service;}
    @GetMapping("/failures") public List<OutboxRecoveryService.FailureView> failures(){return service.failures();}
    @GetMapping("/retry-audits") public List<OutboxRetryAudit> audits(){return service.audits();}
    @GetMapping("/failures/page") public OutboxRecoveryService.FailurePage failurePage(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){validate(page,size);return service.failurePage(page,size);}
    @GetMapping("/retry-audits/page") public OutboxRecoveryService.AuditPage auditPage(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){validate(page,size);return service.auditPage(page,size);}
    @PostMapping("/failures/{id}/retry") public OutboxRecoveryService.FailureView retry(@PathVariable UUID id,@RequestHeader("X-Operator") String actor){return service.retry(id,actor);}
    private void validate(int page,int size){if(page<0)throw new IllegalArgumentException("page must be zero or greater");if(size<1||size>100)throw new IllegalArgumentException("size must be between 1 and 100");}
}
