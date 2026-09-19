package io.logitrack.replay;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.UUID;

@Service
public class ReplayPlanService {
    private final ReplayPlanRepository plans;
    private final DeadLetterEventRepository events;
    private final ReplayService replay;
    private final int maxBatchSize;
    private final long delayMillis;

    public ReplayPlanService(ReplayPlanRepository plans, DeadLetterEventRepository events, ReplayService replay,
        @Value("${logitrack.replay.batch-max-size:20}") int maxBatchSize,
        @Value("${logitrack.replay.batch-rate-per-second:5}") int ratePerSecond) {
        if(maxBatchSize<1||maxBatchSize>100)throw new IllegalArgumentException("Replay batch maximum must be between 1 and 100");
        if(ratePerSecond<1||ratePerSecond>1000)throw new IllegalArgumentException("Replay rate must be between 1 and 1000 events per second");
        this.plans=plans;this.events=events;this.replay=replay;this.maxBatchSize=maxBatchSize;
        this.delayMillis=Math.max(1,1000/ratePerSecond);
    }

    @Transactional
    public ReplayPlan prepare(CreateReplayPlanRequest request, String actor) {
        var normalizedActor=normalizeActor(actor);
        if(request==null||request.eventIds()==null||request.eventIds().isEmpty()) throw new IllegalArgumentException("eventIds are required");
        if(request.eventIds().stream().anyMatch(Objects::isNull)) throw new IllegalArgumentException("eventIds must not contain null");
        var ids=List.copyOf(new LinkedHashSet<>(request.eventIds()));
        if(ids.size()>maxBatchSize) throw new IllegalArgumentException("Replay batch exceeds maximum size " + maxBatchSize);
        var selected=events.findAllById(ids);
        if(selected.size()!=ids.size()) throw new java.util.NoSuchElementException("One or more DLQ events were not found");
        if(selected.stream().anyMatch(event->event.getStatus()!=DeadLetterEvent.Status.PENDING)) throw new IllegalStateException("Replay plans may contain only PENDING events");
        return plans.save(new ReplayPlan(normalizedActor,ids));
    }

    @Transactional
    public ReplayPlan execute(UUID planId, String actor, String approval) {
        var normalizedActor=normalizeActor(actor);
        if(!"APPROVE".equals(approval)) throw new IllegalArgumentException("X-Replay-Approval must be APPROVE");
        var plan=plans.findByIdForUpdate(planId).orElseThrow(()->new java.util.NoSuchElementException("Replay plan not found"));
        if(!plan.getActor().equals(normalizedActor)) throw new IllegalArgumentException("Replay plan operator does not match X-Operator");
        if(plan.getStatus()!=ReplayPlan.Status.PREPARED) throw new IllegalStateException("Replay plan is not executable");
        if(!plan.getExpiresAt().isAfter(Instant.now())) { plan.expire(); return plan; }
        int succeeded=0,failed=0;
        for(var eventId:plan.getEventIds()) {
            try { replay.replay(eventId,normalizedActor); succeeded++; }
            catch(RuntimeException exception) { failed++; }
            if(succeeded+failed<plan.getEventIds().size()) {
                try { Thread.sleep(delayMillis); } catch(InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new IllegalStateException("Replay interrupted"); }
            }
        }
        plan.complete(succeeded,failed);
        return plan;
    }

    private String normalizeActor(String actor) {
        var normalized=actor==null?"":actor.trim();
        if(normalized.isBlank()||normalized.length()>120) throw new IllegalArgumentException("X-Operator must be 1-120 characters");
        return normalized;
    }
}
