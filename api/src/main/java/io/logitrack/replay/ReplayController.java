package io.logitrack.replay;

import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api/operations")
public class ReplayController {
    private final ReplayService service;
    public ReplayController(ReplayService service){this.service=service;}

    @GetMapping("/dlq")
    public List<DeadLetterEvent> list(@RequestParam(required=false) DeadLetterEvent.Status status){return service.list(status);}

    @PostMapping("/dlq/{id}/replay")
    public DeadLetterEvent replay(@PathVariable UUID id, @RequestHeader("X-Operator") String actor){return service.replay(id,actor);}

    @GetMapping("/replay-audits")
    public List<ReplayAudit> audits(){return service.audits();}
}

