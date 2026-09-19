package io.logitrack.route;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface RouteSnapshotRepository extends JpaRepository<RouteSnapshot,UUID> {
    List<RouteSnapshot> findAllByOrderByGeneratedAtDesc();
    Optional<RouteSnapshot> findTopByDeliveryIdOrderByGeneratedAtDesc(UUID deliveryId);
}
