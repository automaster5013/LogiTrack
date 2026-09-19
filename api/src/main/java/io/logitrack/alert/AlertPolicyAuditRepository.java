package io.logitrack.alert;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface AlertPolicyAuditRepository extends JpaRepository<AlertPolicyAudit,UUID> {
    List<AlertPolicyAudit> findTop50ByOrderByOccurredAtDesc();
}
