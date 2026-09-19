package io.logitrack.alert;
import org.springframework.web.bind.annotation.*;
import java.util.List;
@RestController @RequestMapping("/api/alerts")
public class AlertController {
    private final DeliveryAlertRepository repository;
    public AlertController(DeliveryAlertRepository repository){this.repository=repository;}
    @GetMapping public List<DeliveryAlert> list(){return repository.findAllByOrderByLastObservedAtDesc();}
}

