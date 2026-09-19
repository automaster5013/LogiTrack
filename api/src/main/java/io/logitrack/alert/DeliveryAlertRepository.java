package io.logitrack.alert;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface DeliveryAlertRepository extends JpaRepository<DeliveryAlert,UUID> {
    Optional<DeliveryAlert> findByDeliveryIdAndAlertTypeAndStatus(UUID deliveryId,DeliveryAlert.Type alertType,DeliveryAlert.Status status);
    List<DeliveryAlert> findAllByOrderByLastObservedAtDesc();
}

