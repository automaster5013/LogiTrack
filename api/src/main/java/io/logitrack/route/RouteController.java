package io.logitrack.route;
import org.springframework.web.bind.annotation.*;
import java.util.List;
@RestController @RequestMapping("/api/routes")
public class RouteController {
    private final RouteSnapshotRepository repository;
    public RouteController(RouteSnapshotRepository repository){this.repository=repository;}
    @GetMapping public List<RouteSnapshot> list(){return repository.findAllByOrderByGeneratedAtDesc();}
}
