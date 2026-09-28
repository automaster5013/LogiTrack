package io.logitrack.delivery;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.time.Instant;
import java.util.*;

public interface DeliveryRepository extends JpaRepository<Delivery, UUID> {
    long countByStatusIn(Collection<Delivery.Status> statuses);
    @Query("SELECT COUNT(d) FROM Delivery d WHERE d.status IN :statuses AND d.vehicleId LIKE 'TRUCK-DEMO-%' AND COALESCE(d.lastTelemetryAt,d.createdAt) >= :cutoff")
    long countFreshDemoActive(@Param("statuses") Collection<Delivery.Status> statuses,@Param("cutoff") Instant cutoff);
    Optional<Delivery> findByIdempotencyKey(String idempotencyKey);
    Optional<Delivery> findByOrderId(UUID orderId);
    List<Delivery> findByOrderIdIn(Collection<UUID> orderIds);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(:key,0))",nativeQuery=true)
    void lockIdempotencyKey(@Param("key") String key);
}
