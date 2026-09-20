package io.logitrack.replay;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;
import java.time.Instant;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;

public interface DeadLetterEventRepository extends JpaRepository<DeadLetterEvent, UUID> {
    boolean existsByDlqTopicAndDlqPartitionAndDlqOffset(String topic, int partition, long offset);
    List<DeadLetterEvent> findTop100ByOrderByFailedAtDesc();
    List<DeadLetterEvent> findTop100ByStatusOrderByFailedAtDesc(DeadLetterEvent.Status status);
    Page<DeadLetterEvent> findByStatus(DeadLetterEvent.Status status,Pageable pageable);
    long countByStatus(DeadLetterEvent.Status status);
    @Modifying @Query(value="DELETE FROM dead_letter_events WHERE id IN (SELECT id FROM dead_letter_events WHERE status IN ('REPLAYED','DISCARDED') AND COALESCE(replayed_at,discarded_at) < :cutoff ORDER BY COALESCE(replayed_at,discarded_at) LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteTerminalBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select event from DeadLetterEvent event where event.id=:id")
    Optional<DeadLetterEvent> lockById(@Param("id") UUID id);
}
