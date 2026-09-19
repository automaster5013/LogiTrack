package io.logitrack.route;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.*;
public interface RouteSnapshotRepository extends JpaRepository<RouteSnapshot,UUID> {
    List<RouteSnapshot> findAllByOrderByGeneratedAtDesc();
    @Query(value="""
        SELECT DISTINCT ON (delivery_id) *
        FROM route_snapshots
        WHERE delivery_id IN (:deliveryIds)
        ORDER BY delivery_id, generated_at DESC, id DESC
        """,nativeQuery=true)
    List<RouteSnapshot> findLatestByDeliveryIdIn(@Param("deliveryIds") Collection<UUID> deliveryIds);
    Optional<RouteSnapshot> findTopByDeliveryIdOrderByGeneratedAtDesc(UUID deliveryId);
}
