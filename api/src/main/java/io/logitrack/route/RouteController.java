package io.logitrack.route;
import org.springframework.web.bind.annotation.*;
import org.springframework.data.domain.PageRequest;
import java.util.*;
@RestController @RequestMapping("/api/routes")
public class RouteController {
    private final RouteSnapshotRepository repository;
    public RouteController(RouteSnapshotRepository repository){this.repository=repository;}
    @GetMapping public List<RouteSnapshot> list(@RequestParam(required=false) List<UUID> deliveryIds,@RequestParam(defaultValue="200") int limit){
        if(limit<1||limit>500)throw new IllegalArgumentException("limit must be between 1 and 500");
        if(deliveryIds==null)return repository.findAllByOrderByGeneratedAtDesc(PageRequest.of(0,limit));
        var ids=new LinkedHashSet<>(deliveryIds);if(ids.size()>100)throw new IllegalArgumentException("At most 100 deliveryIds are allowed");
        return ids.isEmpty()?List.of():repository.findLatestByDeliveryIdIn(ids);
    }
}
