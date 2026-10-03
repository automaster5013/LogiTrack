package io.logitrack.alert;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;

public interface AlertPolicyRepository extends JpaRepository<AlertPolicy,UUID> {
    Optional<AlertPolicy> findByVehicleId(String vehicleId);
    @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("select policy from AlertPolicy policy where policy.vehicleId=:vehicleId") Optional<AlertPolicy> findByVehicleIdForUpdate(@Param("vehicleId") String vehicleId);
    Optional<AlertPolicy> findByVehicleIdAndActiveTrue(String vehicleId);
    List<AlertPolicy> findAllByActiveTrueOrderByVehicleIdAsc();
}
