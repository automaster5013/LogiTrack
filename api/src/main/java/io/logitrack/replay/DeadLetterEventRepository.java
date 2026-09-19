package io.logitrack.replay;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;

public interface DeadLetterEventRepository extends JpaRepository<DeadLetterEvent, UUID> {
    boolean existsByDlqTopicAndDlqPartitionAndDlqOffset(String topic, int partition, long offset);
    List<DeadLetterEvent> findTop100ByOrderByFailedAtDesc();
    List<DeadLetterEvent> findTop100ByStatusOrderByFailedAtDesc(DeadLetterEvent.Status status);
    long countByStatus(DeadLetterEvent.Status status);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select event from DeadLetterEvent event where event.id=:id")
    Optional<DeadLetterEvent> lockById(@Param("id") UUID id);
}
