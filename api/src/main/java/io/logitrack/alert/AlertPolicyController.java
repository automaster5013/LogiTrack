package io.logitrack.alert;

import org.springframework.web.bind.annotation.*;
import java.util.List;

@RestController
@RequestMapping("/api/alert-policies")
public class AlertPolicyController {
    private final AlertPolicyService service;
    public AlertPolicyController(AlertPolicyService service){this.service=service;}
    @GetMapping public List<AlertPolicy> list(){return service.list();}
    @GetMapping("/audits") public List<AlertPolicyAudit> audits(){return service.auditTrail();}
    @PostMapping public AlertPolicy upsert(@RequestBody UpsertAlertPolicyRequest request,@RequestHeader("X-Operator") String actor){return service.upsert(request,actor);}
}
