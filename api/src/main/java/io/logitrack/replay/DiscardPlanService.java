package io.logitrack.replay;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import io.logitrack.config.InputLimits;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

@Service
public class DiscardPlanService {
    private final DiscardPlanRepository plans;
    private final DeadLetterEventRepository events;
    private final ReplayService replay;
    private final int maxBatchSize;

    public DiscardPlanService(DiscardPlanRepository plans,DeadLetterEventRepository events,ReplayService replay,
        @Value("${logitrack.replay.batch-max-size:20}") int maxBatchSize){
        if(maxBatchSize<1||maxBatchSize>100)throw new IllegalArgumentException("Discard batch maximum must be between 1 and 100");
        this.plans=plans;this.events=events;this.replay=replay;this.maxBatchSize=maxBatchSize;
    }

    @Transactional
    public DiscardPlan prepare(CreateDiscardPlanRequest request,String actor,String requestKey){
        var normalizedActor=normalizeActor(actor);
        if(request==null||request.eventIds()==null||request.eventIds().isEmpty())throw new IllegalArgumentException("eventIds are required");
        if(request.eventIds().stream().anyMatch(Objects::isNull))throw new IllegalArgumentException("eventIds must not contain null");
        var reason=normalizeReason(request.reason());
        var ids=List.copyOf(new LinkedHashSet<>(request.eventIds()));
        if(ids.size()>maxBatchSize)throw new IllegalArgumentException("Discard batch exceeds maximum size "+maxBatchSize);
        InputLimits.required(requestKey,"Idempotency-Key",160);plans.lockRequestKey(requestKey);
        var prior=plans.findByRequestKey(requestKey);
        if(prior.isPresent()){
            var completed=prior.get();
            if(!completed.getActor().equals(normalizedActor)||!completed.getReason().equals(reason)||!completed.getEventIds().equals(ids))throw new IllegalStateException("Idempotency key was used with a different discard plan request");
            return completed;
        }
        var selected=events.findAllById(ids);
        if(selected.size()!=ids.size())throw new java.util.NoSuchElementException("One or more DLQ events were not found");
        if(selected.stream().anyMatch(event->event.getStatus()!=DeadLetterEvent.Status.PENDING))throw new IllegalStateException("Discard plans may contain only PENDING events");
        return plans.save(new DiscardPlan(normalizedActor,requestKey,reason,ids));
    }

    @Transactional
    public DiscardPlan execute(UUID planId,String actor,String approval){
        return execute(planId,actor,approval,null);
    }

    @Transactional
    public DiscardPlan execute(UUID planId,String actor,String approval,String requestKey){
        var normalizedActor=normalizeActor(actor);
        if(!"DISCARD".equals(approval))throw new IllegalArgumentException("X-Discard-Approval must be DISCARD");
        if(requestKey!=null){
            InputLimits.required(requestKey,"Idempotency-Key",160);plans.lockExecutionRequestKey(requestKey);
            var prior=plans.findByExecutionRequestKey(requestKey);
            if(prior.isPresent()){
                if(!prior.get().getId().equals(planId)||!prior.get().getActor().equals(normalizedActor))throw new IllegalStateException("Idempotency key was used with a different discard plan execution");
                return prior.get();
            }
        }
        var plan=plans.findByIdForUpdate(planId).orElseThrow(()->new java.util.NoSuchElementException("Discard plan not found"));
        if(!plan.getActor().equals(normalizedActor))throw new IllegalArgumentException("Discard plan operator does not match X-Operator");
        if(plan.getStatus()!=DiscardPlan.Status.PREPARED){if(requestKey!=null)plan.bindExecutionRequest(requestKey);return plan;}
        if(requestKey!=null)plan.bindExecutionRequest(requestKey);
        if(!plan.getExpiresAt().isAfter(Instant.now())){plan.expire();return plan;}
        int succeeded=0,failed=0;
        for(var eventId:plan.getEventIds()){
            try{replay.discard(eventId,normalizedActor,plan.getReason());succeeded++;}
            catch(RuntimeException exception){failed++;}
        }
        plan.complete(succeeded,failed);
        return plan;
    }

    private String normalizeActor(String actor){var normalized=actor==null?"":actor.trim();if(normalized.isBlank()||normalized.length()>120)throw new IllegalArgumentException("X-Operator must be 1-120 characters");return normalized;}
    private String normalizeReason(String reason){var normalized=reason==null?"":reason.trim();if(normalized.isBlank()||normalized.length()>500)throw new IllegalArgumentException("reason must be 1-500 characters");return normalized;}
}
