package io.logitrack.replay;

import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/operations")
public class ReplayController {
    private final ReplayService service;
    private final ReplayPlanService plans;
    private final DiscardPlanService discardPlans;
    public ReplayController(ReplayService service, ReplayPlanService plans,DiscardPlanService discardPlans){this.service=service;this.plans=plans;this.discardPlans=discardPlans;}

    @GetMapping("/dlq")
    public List<DeadLetterEvent> list(@RequestParam(required=false) DeadLetterEvent.Status status){return service.list(status);}

    @PostMapping("/dlq/{id}/replay")
    public DeadLetterEvent replay(@PathVariable UUID id, @RequestHeader("X-Operator") String actor){return service.replay(id,actor);}

    @PostMapping("/dlq/{id}/discard")
    public DeadLetterEvent discard(@PathVariable UUID id, @RequestHeader("X-Operator") String actor, @RequestBody DiscardRequest request){return service.discard(id,actor,request.reason());}

    @GetMapping("/replay-audits")
    public List<ReplayAudit> audits(){return service.audits();}

    @PostMapping("/replay-plans")
    public ReplayPlan prepare(@RequestBody CreateReplayPlanRequest request, @RequestHeader("X-Operator") String actor){return plans.prepare(request,actor);}

    @PostMapping("/replay-plans/{id}/execute")
    public ReplayPlan execute(@PathVariable UUID id, @RequestHeader("X-Operator") String actor,
        @RequestHeader("X-Replay-Approval") String approval){return plans.execute(id,actor,approval);}

    @PostMapping("/discard-plans")
    public DiscardPlan prepareDiscard(@RequestBody CreateDiscardPlanRequest request,@RequestHeader("X-Operator") String actor){return discardPlans.prepare(request,actor);}

    @PostMapping("/discard-plans/{id}/execute")
    public DiscardPlan executeDiscard(@PathVariable UUID id,@RequestHeader("X-Operator") String actor,
        @RequestHeader("X-Discard-Approval") String approval){return discardPlans.execute(id,actor,approval);}

    public record DiscardRequest(String reason) {}
}
