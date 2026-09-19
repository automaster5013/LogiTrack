package io.logitrack.alert;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.*;

@Service
public class AlertPolicyService {
    private final AlertPolicyRepository policies; private final AlertPolicyAuditRepository audits;
    public AlertPolicyService(AlertPolicyRepository policies,AlertPolicyAuditRepository audits){this.policies=policies;this.audits=audits;}
    @Transactional(readOnly=true)
    public AlertPolicy resolve(String vehicleId){return policies.findByVehicleIdAndActiveTrue(vehicleId).orElseGet(()->policies.findByVehicleIdAndActiveTrue(AlertPolicy.DEFAULT_VEHICLE)
        .orElseThrow(()->new IllegalStateException("Default alert policy is missing")));}
    @Transactional(readOnly=true) public List<AlertPolicy> list(){return policies.findAllByActiveTrueOrderByVehicleIdAsc();}
    @Transactional(readOnly=true) public List<AlertPolicyAudit> auditTrail(){return audits.findTop50ByOrderByOccurredAtDesc();}
    @Transactional
    public AlertPolicy upsert(UpsertAlertPolicyRequest request,String actor){
        var vehicle=normalize("vehicleId",request.vehicleId());var operator=normalize("X-Operator",actor);
        var existing=policies.findByVehicleId(vehicle);
        var policy=existing.orElseGet(()->new AlertPolicy(vehicle,request.deviationOpenMeters(),request.deviationCloseMeters(),
            request.criticalDeviationMeters(),request.delayOpenSeconds(),request.delayCloseSeconds(),request.criticalDelaySeconds(),operator));
        if(existing.isPresent())policy.update(request.deviationOpenMeters(),request.deviationCloseMeters(),request.criticalDeviationMeters(),
            request.delayOpenSeconds(),request.delayCloseSeconds(),request.criticalDelaySeconds(),operator);
        policy=policies.save(policy);audits.save(new AlertPolicyAudit(policy,operator));return policy;
    }
    @Transactional
    public AlertPolicy reset(String vehicleId,String actor){
        var vehicle=normalize("vehicleId",vehicleId);var operator=normalize("X-Operator",actor);
        if(AlertPolicy.DEFAULT_VEHICLE.equals(vehicle))throw new IllegalArgumentException("Global default policy cannot be reset");
        var policy=policies.findByVehicleIdAndActiveTrue(vehicle).orElseThrow(()->new NoSuchElementException("Active vehicle alert policy not found"));
        policy.deactivate(operator);policy=policies.save(policy);audits.save(new AlertPolicyAudit(policy,operator,AlertPolicyAudit.Action.RESET));return policy;
    }
    private String normalize(String field,String value){var normalized=value==null?"":value.trim();
        if(normalized.isBlank()||normalized.length()>120)throw new IllegalArgumentException(field+" must be 1-120 characters");return normalized;}
}
