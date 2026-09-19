package io.logitrack.event;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import java.time.Instant;
import java.util.UUID;
public interface ProcessedEventRepository extends JpaRepository<ProcessedEvent, UUID> {
    @Modifying @Query(value="DELETE FROM processed_events WHERE event_id IN (SELECT event_id FROM processed_events WHERE processed_at < :cutoff ORDER BY processed_at LIMIT :batchSize FOR UPDATE SKIP LOCKED)",nativeQuery=true)
    int deleteBatchBefore(@Param("cutoff") Instant cutoff,@Param("batchSize") int batchSize);
}
