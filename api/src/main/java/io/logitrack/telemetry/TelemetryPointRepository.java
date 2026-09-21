package io.logitrack.telemetry;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.time.Instant;
import java.util.*;
public interface TelemetryPointRepository extends JpaRepository<TelemetryPoint,UUID> {
    List<TelemetryPoint> findTop5000ByOrderByOccurredAtDescEventIdDesc();
    @Query(value="""
        WITH ranked AS (
            SELECT tp.*, ROW_NUMBER() OVER (
                PARTITION BY delivery_id ORDER BY occurred_at DESC, event_id DESC
            ) AS delivery_rank
            FROM telemetry_points tp
            WHERE delivery_id IN (:deliveryIds)
        ), selected AS (
            SELECT event_id, delivery_id, vehicle_id, latitude, longitude, progress, occurred_at
            FROM ranked
            ORDER BY CASE WHEN delivery_rank = 1 THEN 0 ELSE 1 END, occurred_at DESC, event_id DESC
            LIMIT 5000
        )
        SELECT * FROM selected ORDER BY occurred_at DESC, event_id DESC
        """,nativeQuery=true)
    List<TelemetryPoint> findRecentWithLatestPerDelivery(@Param("deliveryIds") Collection<UUID> deliveryIds);
    @Modifying @Query(value="DELETE FROM telemetry_points WHERE event_id IN (SELECT event_id FROM telemetry_points WHERE occurred_at < :cutoff ORDER BY occurred_at LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
}
