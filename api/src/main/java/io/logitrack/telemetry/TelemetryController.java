package io.logitrack.telemetry;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/telemetry/points")
public class TelemetryController {
    private final TelemetryPointRepository repository;
    public TelemetryController(TelemetryPointRepository repository){this.repository=repository;}
    @GetMapping public List<TelemetryPoint> list(@RequestParam(required=false) List<UUID> deliveryIds){
        if(deliveryIds==null)return repository.findTop5000ByOrderByOccurredAtDesc();
        var ids=new LinkedHashSet<>(deliveryIds);if(ids.size()>100)throw new IllegalArgumentException("At most 100 deliveryIds are allowed");
        return ids.isEmpty()?List.of():repository.findTop5000ByDeliveryIdInOrderByOccurredAtDesc(ids);
    }
}
