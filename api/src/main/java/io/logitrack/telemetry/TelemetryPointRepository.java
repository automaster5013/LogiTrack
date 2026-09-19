package io.logitrack.telemetry;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.time.Instant;
import java.util.*;
public interface TelemetryPointRepository extends JpaRepository<TelemetryPoint,UUID> {
    List<TelemetryPoint> findTop5000ByOrderByOccurredAtDesc();
    List<TelemetryPoint> findTop5000ByDeliveryIdInOrderByOccurredAtDesc(Collection<UUID> deliveryIds);
    @Modifying @Query(value="DELETE FROM telemetry_points WHERE event_id IN (SELECT event_id FROM telemetry_points WHERE occurred_at < :cutoff ORDER BY occurred_at LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
}
