package io.logitrack.telemetry;
import org.springframework.web.bind.annotation.*;
import java.util.List;
@RestController @RequestMapping("/api/telemetry/points")
public class TelemetryController {
    private final TelemetryPointRepository repository;
    public TelemetryController(TelemetryPointRepository repository){this.repository=repository;}
    @GetMapping public List<TelemetryPoint> list(){return repository.findTop5000ByOrderByOccurredAtDesc();}
}
