package io.logitrack.outbox;
import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface OutboxRetryAuditRepository extends JpaRepository<OutboxRetryAudit,UUID> {
    List<OutboxRetryAudit> findTop50ByOrderByOccurredAtDesc();
}
