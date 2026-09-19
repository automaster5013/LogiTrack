package io.logitrack.outbox;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import org.springframework.stereotype.Repository;
import java.util.*;

@Repository
public interface OutboxRepository extends JpaRepository<OutboxEvent, UUID> {
    @Query(value="SELECT * FROM outbox_events WHERE status = 'PENDING' AND next_attempt_at <= CURRENT_TIMESTAMP ORDER BY next_attempt_at, created_at LIMIT :batchSize FOR UPDATE SKIP LOCKED",nativeQuery=true)
    List<OutboxEvent> lockPendingBatch(@Param("batchSize") int batchSize);
    List<OutboxEvent> findTop50ByStatusOrderByCreatedAtDesc(OutboxEvent.Status status);
    long countByStatus(OutboxEvent.Status status);
    Optional<OutboxEvent> findFirstByStatusOrderByCreatedAtAsc(OutboxEvent.Status status);
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("select event from OutboxEvent event where event.id=:id")
    Optional<OutboxEvent> lockById(@Param("id") UUID id);
}
