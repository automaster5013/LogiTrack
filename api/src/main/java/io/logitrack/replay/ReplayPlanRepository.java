package io.logitrack.replay;

import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;
import java.util.UUID;

public interface ReplayPlanRepository extends JpaRepository<ReplayPlan, UUID> {
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select p from ReplayPlan p where p.id=:id")
    Optional<ReplayPlan> findByIdForUpdate(@Param("id") UUID id);
}

