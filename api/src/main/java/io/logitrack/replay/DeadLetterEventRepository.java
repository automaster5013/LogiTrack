package io.logitrack.replay;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface DeadLetterEventRepository extends JpaRepository<DeadLetterEvent, UUID> {
    boolean existsByDlqTopicAndDlqPartitionAndDlqOffset(String topic, int partition, long offset);
    List<DeadLetterEvent> findTop100ByOrderByFailedAtDesc();
    List<DeadLetterEvent> findTop100ByStatusOrderByFailedAtDesc(DeadLetterEvent.Status status);
}

