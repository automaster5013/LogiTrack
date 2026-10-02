package io.logitrack.alert;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;

public interface AlertPolicyAuditRepository extends JpaRepository<AlertPolicyAudit,UUID> {
    List<AlertPolicyAudit> findTop50ByOrderByOccurredAtDesc();
    Optional<AlertPolicyAudit> findByRestoredFromAuditIdAndActor(UUID restoredFromAuditId,String actor);
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("select audit from AlertPolicyAudit audit where audit.id=:id") Optional<AlertPolicyAudit> findByIdForUpdate(@Param("id") UUID id);
}
