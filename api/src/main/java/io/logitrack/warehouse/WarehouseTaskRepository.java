package io.logitrack.warehouse;
import org.springframework.data.jpa.repository.JpaRepository; import java.util.*;
public interface WarehouseTaskRepository extends JpaRepository<WarehouseTask,UUID>{Optional<WarehouseTask> findByIdempotencyKey(String key);List<WarehouseTask> findAllByOrderByCreatedAtDesc();}

