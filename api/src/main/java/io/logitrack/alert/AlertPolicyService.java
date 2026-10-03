package io.logitrack.alert;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.*;
import io.logitrack.config.InputLimits;
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
    @Transactional(readOnly=true) public AuditPage auditPage(int page,int size){var result=audits.findAll(PageRequest.of(page,size,Sort.by(Sort.Direction.DESC,"occurredAt").and(Sort.by(Sort.Direction.DESC,"id"))));return new AuditPage(result.getContent(),result.getNumber(),result.getSize(),result.getTotalElements(),result.hasNext());}
    public record AuditPage(List<AlertPolicyAudit> items,int page,int size,long totalElements,boolean hasMore){}
    @Transactional
    public AlertPolicy upsert(UpsertAlertPolicyRequest request,String actor,String requestKey){
        if(request==null)throw new IllegalArgumentException("Alert policy request is required");
        var vehicle=normalize("vehicleId",request.vehicleId());var operator=normalize("X-Operator",actor);
        InputLimits.required(requestKey,"Idempotency-Key",160);audits.lockRequestKey(requestKey);
        var prior=audits.findByRequestKey(requestKey);
        if(prior.isPresent()){
            var completed=prior.get();
            if(completed.getAction()!=AlertPolicyAudit.Action.UPSERT||!completed.getActor().equals(operator)||!matches(request,completed))throw new IllegalStateException("Idempotency key was used with a different alert policy request");
            var current=policies.findByVehicleId(vehicle).orElseThrow(()->new IllegalStateException("Saved alert policy no longer exists"));
            if(matches(current,completed)&&current.isActive()&&current.getUpdatedBy().equals(operator)&&current.getUpdatedAt().equals(completed.getPolicyUpdatedAt()))return current;
            throw new IllegalStateException("Saved alert policy has changed since this request completed");
        }
        var existing=policies.findByVehicleId(vehicle);
        var policy=existing.orElseGet(()->new AlertPolicy(vehicle,request.deviationOpenMeters(),request.deviationCloseMeters(),
            request.criticalDeviationMeters(),request.delayOpenSeconds(),request.delayCloseSeconds(),request.criticalDelaySeconds(),operator));
        if(existing.isPresent())policy.update(request.deviationOpenMeters(),request.deviationCloseMeters(),request.criticalDeviationMeters(),
            request.delayOpenSeconds(),request.delayCloseSeconds(),request.criticalDelaySeconds(),operator);
        policy=policies.save(policy);audits.save(new AlertPolicyAudit(policy,operator,requestKey));return policy;
    }
    @Transactional
    public AlertPolicy reset(String vehicleId,String actor){
        return reset(vehicleId,actor,null);
    }
    @Transactional
    public AlertPolicy reset(String vehicleId,String actor,String requestKey){
        var vehicle=normalize("vehicleId",vehicleId);var operator=normalize("X-Operator",actor);
        if(AlertPolicy.DEFAULT_VEHICLE.equals(vehicle))throw new IllegalArgumentException("Global default policy cannot be reset");
        if(requestKey!=null){
            InputLimits.required(requestKey,"Idempotency-Key",160);audits.lockRequestKey(requestKey);
            var prior=audits.findByRequestKey(requestKey);
            if(prior.isPresent()){
                var completed=prior.get();
                if(completed.getAction()!=AlertPolicyAudit.Action.RESET||!completed.getActor().equals(operator)||!completed.getVehicleId().equals(vehicle))throw new IllegalStateException("Idempotency key was used with a different alert policy request");
                var current=policies.findByVehicleId(vehicle).orElseThrow(()->new IllegalStateException("Reset alert policy no longer exists"));
                if(matches(current,completed)&&!current.isActive()&&current.getUpdatedBy().equals(operator)&&current.getUpdatedAt().equals(completed.getPolicyUpdatedAt()))return current;
                throw new IllegalStateException("Reset alert policy has changed since this request completed");
            }
        }
        var policy=policies.findByVehicleId(vehicle).orElseThrow(()->new NoSuchElementException("Vehicle alert policy not found"));
        if(!policy.isActive()){
            if(requestKey!=null)throw new IllegalStateException("Vehicle alert policy has already been reset");
            if(policy.getUpdatedBy().equals(operator))return policy;
            throw new IllegalStateException("Vehicle alert policy has already been reset");
        }
        policy.deactivate(operator);policy=policies.save(policy);audits.save(new AlertPolicyAudit(policy,operator,AlertPolicyAudit.Action.RESET,requestKey));return policy;
    }
    @Transactional
    public AlertPolicy restore(UUID auditId,String actor){
        return restore(auditId,actor,null);
    }
    @Transactional
    public AlertPolicy restore(UUID auditId,String actor,String requestKey){
        var operator=normalize("X-Operator",actor);
        if(requestKey!=null){
            InputLimits.required(requestKey,"Idempotency-Key",160);audits.lockRequestKey(requestKey);
            var completed=audits.findByRequestKey(requestKey);
            if(completed.isPresent()){
                var prior=completed.get();
                if(prior.getAction()!=AlertPolicyAudit.Action.RESTORE||!prior.getActor().equals(operator)||!Objects.equals(prior.getRestoredFromAuditId(),auditId))throw new IllegalStateException("Idempotency key was used with a different alert policy request");
                var current=policies.findByVehicleId(prior.getVehicleId()).orElseThrow(()->new IllegalStateException("Restored alert policy no longer exists"));
                if(matches(current,prior)&&current.isActive()&&current.getUpdatedBy().equals(operator)&&current.getUpdatedAt().equals(prior.getPolicyUpdatedAt()))return current;
                throw new IllegalStateException("Restored alert policy has changed since this request completed");
            }
        }
        var snapshot=audits.findByIdForUpdate(Objects.requireNonNull(auditId,"auditId must be provided"))
            .orElseThrow(()->new NoSuchElementException("Alert policy audit snapshot not found"));
        var prior=audits.findByRestoredFromAuditIdAndActor(snapshot.getId(),operator);
        if(prior.isPresent()){
            var current=policies.findByVehicleId(snapshot.getVehicleId()).orElseThrow(()->new IllegalStateException("Restored alert policy no longer exists"));
            if(matches(current,prior.get())&&current.isActive()&&current.getUpdatedBy().equals(operator)){
                if(requestKey!=null)prior.get().bindRequestKey(requestKey);
                return current;
            }
            throw new IllegalStateException("Restored alert policy has changed since this request completed");
        }
        var existing=policies.findByVehicleId(snapshot.getVehicleId());
        var policy=existing.orElseGet(()->new AlertPolicy(snapshot.getVehicleId(),snapshot.getDeviationOpenMeters(),snapshot.getDeviationCloseMeters(),
            snapshot.getCriticalDeviationMeters(),snapshot.getDelayOpenSeconds(),snapshot.getDelayCloseSeconds(),snapshot.getCriticalDelaySeconds(),operator));
        if(existing.isPresent())policy.update(snapshot.getDeviationOpenMeters(),snapshot.getDeviationCloseMeters(),snapshot.getCriticalDeviationMeters(),
            snapshot.getDelayOpenSeconds(),snapshot.getDelayCloseSeconds(),snapshot.getCriticalDelaySeconds(),operator);
        policy=policies.save(policy);audits.save(new AlertPolicyAudit(policy,operator,snapshot.getId(),requestKey));return policy;
    }
    private boolean matches(AlertPolicy policy,AlertPolicyAudit audit){return Double.compare(policy.getDeviationOpenMeters(),audit.getDeviationOpenMeters())==0
        &&Double.compare(policy.getDeviationCloseMeters(),audit.getDeviationCloseMeters())==0&&Double.compare(policy.getCriticalDeviationMeters(),audit.getCriticalDeviationMeters())==0
        &&policy.getDelayOpenSeconds()==audit.getDelayOpenSeconds()&&policy.getDelayCloseSeconds()==audit.getDelayCloseSeconds()&&policy.getCriticalDelaySeconds()==audit.getCriticalDelaySeconds();}
    private boolean matches(UpsertAlertPolicyRequest request,AlertPolicyAudit audit){return request.vehicleId().trim().equals(audit.getVehicleId())
        &&Double.compare(request.deviationOpenMeters(),audit.getDeviationOpenMeters())==0&&Double.compare(request.deviationCloseMeters(),audit.getDeviationCloseMeters())==0
        &&Double.compare(request.criticalDeviationMeters(),audit.getCriticalDeviationMeters())==0&&request.delayOpenSeconds()==audit.getDelayOpenSeconds()
        &&request.delayCloseSeconds()==audit.getDelayCloseSeconds()&&request.criticalDelaySeconds()==audit.getCriticalDelaySeconds();}
    private String normalize(String field,String value){var normalized=value==null?"":value.trim();
        if(normalized.isBlank()||normalized.length()>120)throw new IllegalArgumentException(field+" must be 1-120 characters");return normalized;}
}
