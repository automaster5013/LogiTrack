package io.logitrack.delivery;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;
import java.time.Instant;
import java.util.*;

public interface DeliveryRepository extends JpaRepository<Delivery, UUID> {
    long countByStatusIn(Collection<Delivery.Status> statuses);
    @Query("SELECT COUNT(d) FROM Delivery d WHERE d.status IN :statuses AND d.vehicleId LIKE 'TRUCK-DEMO-%' AND COALESCE(d.lastTelemetryAt,d.createdAt) >= :cutoff")
    long countFreshDemoActive(@Param("statuses") Collection<Delivery.Status> statuses,@Param("cutoff") Instant cutoff);
    @Transactional
    @Modifying(clearAutomatically=true)
    @Query(value="DELETE FROM deliveries WHERE id IN (SELECT id FROM deliveries WHERE status='DELIVERED' AND vehicle_id LIKE 'TRUCK-DEMO-%' AND updated_at < :cutoff ORDER BY updated_at LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteCompletedDemoBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
    Optional<Delivery> findByIdempotencyKey(String idempotencyKey);
    Optional<Delivery> findByOrderId(UUID orderId);
    List<Delivery> findByOrderIdIn(Collection<UUID> orderIds);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(:key,0))",nativeQuery=true)
    void lockIdempotencyKey(@Param("key") String key);
}
