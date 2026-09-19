package io.logitrack.delivery;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface DeliveryRepository extends JpaRepository<Delivery, UUID> {
    Optional<Delivery> findByIdempotencyKey(String idempotencyKey);
    Optional<Delivery> findByOrderId(UUID orderId);
}
