package io.logitrack.alert;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;

public interface AlertPolicyRepository extends JpaRepository<AlertPolicy,UUID> {
    Optional<AlertPolicy> findByVehicleId(String vehicleId);
    List<AlertPolicy> findAllByOrderByVehicleIdAsc();
}
