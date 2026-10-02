package io.logitrack.outbox;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.*;
public interface OutboxRetryAuditRepository extends JpaRepository<OutboxRetryAudit,UUID> {
    List<OutboxRetryAudit> findTop50ByOrderByOccurredAtDesc();
    Optional<OutboxRetryAudit> findByRequestKey(String requestKey);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('outbox-retry:',:key),0))",nativeQuery=true)
    void lockRequestKey(@Param("key") String key);
}
