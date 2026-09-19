package io.logitrack.telemetry;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface TelemetryPointRepository extends JpaRepository<TelemetryPoint,UUID> {
    List<TelemetryPoint> findTop5000ByOrderByOccurredAtDesc();
}
