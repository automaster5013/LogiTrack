package io.logitrack.replay;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import java.util.*;

public interface ReplayAuditRepository extends JpaRepository<ReplayAudit, UUID> {
    List<ReplayAudit> findTop100ByOrderByOccurredAtDesc();
    Optional<ReplayAudit> findByRequestKey(String requestKey);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('dlq-recovery:',:key),0))",nativeQuery=true)
    void lockRequestKey(@Param("key") String key);
}

