package io.logitrack.warehouse;
import org.springframework.http.*; import org.springframework.web.bind.annotation.*; import java.util.*;
@RestController @RequestMapping("/api/warehouse")
public class WarehouseController {
 private final WarehouseService service; public WarehouseController(WarehouseService service){this.service=service;}
 @PostMapping("/receipts") ResponseEntity<WarehouseTask> receive(@RequestBody WarehouseCommand c,@RequestHeader("Idempotency-Key") String key,@RequestHeader(value="X-Trace-Id",required=false) String trace){return ResponseEntity.status(HttpStatus.CREATED).body(service.receive(c,key,trace(trace)));}
 @PostMapping("/outbounds") ResponseEntity<WarehouseTask> pick(@RequestBody WarehouseCommand c,@RequestHeader("Idempotency-Key") String key,@RequestHeader(value="X-Trace-Id",required=false) String trace){return ResponseEntity.status(HttpStatus.CREATED).body(service.pick(c,key,trace(trace)));}
 @PostMapping("/outbounds/{id}/dispatch") WarehouseTask dispatch(@PathVariable UUID id,@RequestHeader(value="X-Trace-Id",required=false) String trace){return service.dispatch(id,trace(trace));}
 @GetMapping("/stock") List<WarehouseStock> stock(){return service.stock();} @GetMapping("/tasks") List<WarehouseTask> tasks(){return service.tasks();} @GetMapping("/ledger") List<InventoryLedgerEntry> ledger(){return service.ledger();}
 private String trace(String value){return value==null?UUID.randomUUID().toString():value;}
}
