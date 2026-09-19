package io.logitrack.alert;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import jakarta.persistence.LockModeType;
import org.springframework.data.repository.query.Param;
import java.util.*;
public interface DeliveryAlertRepository extends JpaRepository<DeliveryAlert,UUID> {
    Optional<DeliveryAlert> findByDeliveryIdAndAlertTypeAndStatus(UUID deliveryId,DeliveryAlert.Type alertType,DeliveryAlert.Status status);
    List<DeliveryAlert> findAllByOrderByLastObservedAtDesc();
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select alert from DeliveryAlert alert where alert.id=:id")
    Optional<DeliveryAlert> findByIdForUpdate(@Param("id") UUID id);
}
