package io.logitrack.alert;

import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.*;

public interface AlertPolicyAuditRepository extends JpaRepository<AlertPolicyAudit,UUID> {
    List<AlertPolicyAudit> findTop50ByOrderByOccurredAtDesc();
    Optional<AlertPolicyAudit> findByRequestKey(String requestKey);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('alert-policy-upsert:',:key),0))",nativeQuery=true) void lockRequestKey(@Param("key") String key);
    Optional<AlertPolicyAudit> findByRestoredFromAuditIdAndActor(UUID restoredFromAuditId,String actor);
    Optional<AlertPolicyAudit> findFirstByVehicleIdAndActionAndActorAndPolicyUpdatedAtOrderByOccurredAtDesc(String vehicleId,AlertPolicyAudit.Action action,String actor,Instant policyUpdatedAt);
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("select audit from AlertPolicyAudit audit where audit.id=:id") Optional<AlertPolicyAudit> findByIdForUpdate(@Param("id") UUID id);
}
