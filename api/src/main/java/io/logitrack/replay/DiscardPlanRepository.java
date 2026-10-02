package io.logitrack.replay;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface DiscardPlanRepository extends JpaRepository<DiscardPlan,UUID>{
    Optional<DiscardPlan> findByRequestKey(String requestKey);
    Optional<DiscardPlan> findByExecutionRequestKey(String requestKey);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('discard-plan:',:key),0))",nativeQuery=true)
    void lockRequestKey(@Param("key") String key);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('discard-plan-execution:',:key),0))",nativeQuery=true)
    void lockExecutionRequestKey(@Param("key") String key);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from DiscardPlan p where p.id=:id")
    Optional<DiscardPlan> findByIdForUpdate(@Param("id") UUID id);
}
