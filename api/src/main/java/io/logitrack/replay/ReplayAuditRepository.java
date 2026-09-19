package io.logitrack.replay;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface ReplayAuditRepository extends JpaRepository<ReplayAudit, UUID> {
    List<ReplayAudit> findTop100ByOrderByOccurredAtDesc();
}

