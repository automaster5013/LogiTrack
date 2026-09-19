package io.logitrack.warehouse;
import org.springframework.data.jpa.repository.*; import org.springframework.data.repository.query.Param; import org.springframework.data.domain.Pageable; import java.util.*;
public interface WarehouseTaskRepository extends JpaRepository<WarehouseTask,UUID>{Optional<WarehouseTask> findByIdempotencyKey(String key);List<WarehouseTask> findAllByOrderByCreatedAtDesc(Pageable pageable);@Query(value="SELECT pg_advisory_xact_lock(hashtextextended(:key,0))",nativeQuery=true)void lockIdempotencyKey(@Param("key") String key);}
