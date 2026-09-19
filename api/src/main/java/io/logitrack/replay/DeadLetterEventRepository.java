package io.logitrack.replay;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
import java.time.Instant;

public interface DeadLetterEventRepository extends JpaRepository<DeadLetterEvent, UUID> {
    boolean existsByDlqTopicAndDlqPartitionAndDlqOffset(String topic, int partition, long offset);
    List<DeadLetterEvent> findTop100ByOrderByFailedAtDesc();
    List<DeadLetterEvent> findTop100ByStatusOrderByFailedAtDesc(DeadLetterEvent.Status status);
    long countByStatus(DeadLetterEvent.Status status);
    @Modifying @Query(value="DELETE FROM dead_letter_events WHERE id IN (SELECT id FROM dead_letter_events WHERE status='REPLAYED' AND replayed_at < :cutoff ORDER BY replayed_at LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteReplayedBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select event from DeadLetterEvent event where event.id=:id")
    Optional<DeadLetterEvent> lockById(@Param("id") UUID id);
}
