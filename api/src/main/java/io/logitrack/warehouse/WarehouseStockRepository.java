package io.logitrack.warehouse;
import org.springframework.data.jpa.repository.*; import org.springframework.data.repository.query.Param; import jakarta.persistence.LockModeType; import java.util.*;
public interface WarehouseStockRepository extends JpaRepository<WarehouseStock,UUID>{
 @Lock(LockModeType.PESSIMISTIC_WRITE) @Query("select s from WarehouseStock s where s.warehouseId=:warehouseId and s.sku=:sku")
 Optional<WarehouseStock> lockByWarehouseAndSku(@Param("warehouseId") String warehouseId,@Param("sku") String sku);
 List<WarehouseStock> findAllByOrderByWarehouseIdAscSkuAsc();
}

