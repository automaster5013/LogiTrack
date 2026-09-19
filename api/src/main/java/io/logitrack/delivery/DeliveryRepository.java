package io.logitrack.delivery;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.*;

public interface DeliveryRepository extends JpaRepository<Delivery, UUID> {
    Optional<Delivery> findByIdempotencyKey(String idempotencyKey);
    Optional<Delivery> findByOrderId(UUID orderId);
    List<Delivery> findByOrderIdIn(Collection<UUID> orderIds);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(:key,0))",nativeQuery=true)
    void lockIdempotencyKey(@Param("key") String key);
}
