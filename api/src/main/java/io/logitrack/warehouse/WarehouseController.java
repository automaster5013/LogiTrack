package io.logitrack.warehouse;
import org.springframework.http.*; import org.springframework.web.bind.annotation.*; import java.util.*;
@RestController @RequestMapping("/api/warehouse")
public class WarehouseController {
 private final WarehouseService service; public WarehouseController(WarehouseService service){this.service=service;}
 @PostMapping("/receipts") ResponseEntity<WarehouseTask> receive(@RequestBody WarehouseCommand c,@RequestHeader("Idempotency-Key") String key,@RequestHeader(value="X-Trace-Id",required=false) String trace){return ResponseEntity.status(HttpStatus.CREATED).body(service.receive(c,key,trace(trace)));}
 @PostMapping("/outbounds") ResponseEntity<WarehouseTask> pick(@RequestBody WarehouseCommand c,@RequestHeader("Idempotency-Key") String key,@RequestHeader(value="X-Trace-Id",required=false) String trace){return ResponseEntity.status(HttpStatus.CREATED).body(service.pick(c,key,trace(trace)));}
 @PostMapping("/outbounds/{id}/dispatch") WarehouseTask dispatch(@PathVariable UUID id,@RequestHeader(value="X-Trace-Id",required=false) String trace){return service.dispatch(id,trace(trace));}
 @GetMapping("/stock") List<WarehouseStock> stock(@RequestParam(defaultValue="200") int limit){return service.stock(validLimit(limit));} @GetMapping("/tasks") List<WarehouseTask> tasks(@RequestParam(defaultValue="200") int limit){return service.tasks(validLimit(limit));} @GetMapping("/ledger") List<InventoryLedgerEntry> ledger(){return service.ledger();}
 @GetMapping("/stock/page") WarehouseService.WarehousePage<WarehouseStock> stockPage(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){return service.stockPage(validPage(page),validLimit(size));}
 @GetMapping("/tasks/page") WarehouseService.WarehousePage<WarehouseTask> taskPage(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){return service.taskPage(validPage(page),validLimit(size));}
 @GetMapping("/ledger/page") WarehouseService.WarehousePage<InventoryLedgerEntry> ledgerPage(@RequestParam(defaultValue="0") int page,@RequestParam(defaultValue="100") int size){return service.ledgerPage(validPage(page),validLimit(size));}
 private String trace(String value){return value==null?UUID.randomUUID().toString():value;}
 private int validLimit(int limit){if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");return limit;}
 private int validPage(int page){if(page<0)throw new IllegalArgumentException("page must be zero or greater");return page;}
}
