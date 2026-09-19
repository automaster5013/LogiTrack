package io.logitrack.route;
import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/routes")
public class RouteController {
    private final RouteSnapshotRepository repository;
    public RouteController(RouteSnapshotRepository repository){this.repository=repository;}
    @GetMapping public List<RouteSnapshot> list(@RequestParam(required=false) List<UUID> deliveryIds){
        if(deliveryIds==null)return repository.findAllByOrderByGeneratedAtDesc();
        var ids=new LinkedHashSet<>(deliveryIds);if(ids.size()>100)throw new IllegalArgumentException("At most 100 deliveryIds are allowed");
        return ids.isEmpty()?List.of():repository.findLatestByDeliveryIdIn(ids);
    }
}
