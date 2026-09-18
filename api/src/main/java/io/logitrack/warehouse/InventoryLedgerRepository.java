package io.logitrack.warehouse;
import org.springframework.data.jpa.repository.JpaRepository; import java.util.*;
public interface InventoryLedgerRepository extends JpaRepository<InventoryLedgerEntry,UUID>{List<InventoryLedgerEntry> findTop100ByOrderByOccurredAtDesc();}

