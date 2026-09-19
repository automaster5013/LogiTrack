package io.logitrack.alert;

import org.springframework.web.bind.annotation.*;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/alert-policies")
public class AlertPolicyController {
    private final AlertPolicyService service;
    public AlertPolicyController(AlertPolicyService service){this.service=service;}
    @GetMapping public List<AlertPolicy> list(){return service.list();}
    @GetMapping("/audits") public List<AlertPolicyAudit> audits(){return service.auditTrail();}
    @PostMapping public AlertPolicy upsert(@RequestBody UpsertAlertPolicyRequest request,@RequestHeader("X-Operator") String actor){return service.upsert(request,actor);}
    @PostMapping("/audits/{auditId}/restore") public AlertPolicy restore(@PathVariable UUID auditId,@RequestHeader("X-Operator") String actor){return service.restore(auditId,actor);}
    @DeleteMapping("/{vehicleId}") public void reset(@PathVariable String vehicleId,@RequestHeader("X-Operator") String actor){service.reset(vehicleId,actor);}
}
