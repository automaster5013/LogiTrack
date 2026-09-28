package io.logitrack.delivery;

import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

@Component
@ConditionalOnProperty(name="logitrack.demo.seed-enabled",havingValue="true")
public class DemoDeliverySeeder {
    private static final Logger log=LoggerFactory.getLogger(DemoDeliverySeeder.class);
    private static final List<DemoRoute> ROUTES=List.of(
        new DemoRoute("Seoul Hub",37.5665,126.9780,"Incheon DC",37.4563,126.7052),
        new DemoRoute("Goyang Hub",37.6584,126.8320,"Seoul East",37.5384,127.0823),
        new DemoRoute("Gimpo Depot",37.6153,126.7156,"Songpa DC",37.5145,127.1059),
        new DemoRoute("Incheon Port",37.4485,126.6047,"Seongnam Hub",37.4200,127.1265),
        new DemoRoute("Suwon Hub",37.2636,127.0286,"Yeouido DC",37.5219,126.9245),
        new DemoRoute("Paju Depot",37.7599,126.7800,"Gwangmyeong Hub",37.4786,126.8644),
        new DemoRoute("Namyangju Hub",37.6360,127.2165,"Bucheon DC",37.5034,126.7660),
        new DemoRoute("Hanam Depot",37.5393,127.2148,"Anyang Hub",37.3943,126.9568)
    );
    private static final List<Delivery.Status> ACTIVE_STATUSES=List.of(
        Delivery.Status.CREATED,Delivery.Status.IN_TRANSIT,Delivery.Status.DELAYED);

    private final DeliveryRepository deliveries;
    private final DeliveryService service;
    private final int targetActive;
    private final long staleAfterSeconds;
    private final Duration completedRetention;
    private final int cleanupBatchSize;
    private final MeterRegistry metrics;
    private final AtomicLong cleanupLastSuccessEpochSecond=new AtomicLong();
    private final AtomicLong cleanupMonitorStartedEpochSecond=new AtomicLong();
    private final AtomicLong activeDeliveries=new AtomicLong();
    private final AtomicLong targetDeliveries=new AtomicLong();

    public DemoDeliverySeeder(DeliveryRepository deliveries,DeliveryService service,MeterRegistry metrics,
        @Value("${logitrack.demo.target-active-deliveries:12}") int targetActive,
        @Value("${logitrack.demo.stale-after-seconds:7200}") long staleAfterSeconds,
        @Value("${logitrack.demo.completed-retention:7d}") Duration completedRetention,
        @Value("${logitrack.demo.cleanup-batch-size:250}") int cleanupBatchSize){
        if(targetActive<1||targetActive>50)throw new IllegalArgumentException("demo target must be between 1 and 50");
        if(staleAfterSeconds<60||staleAfterSeconds>86400)throw new IllegalArgumentException("demo stale threshold must be between 60 and 86400 seconds");
        if(completedRetention.compareTo(Duration.ofMinutes(10))<0||completedRetention.compareTo(Duration.ofDays(90))>0)throw new IllegalArgumentException("demo completed retention must be between 10 minutes and 90 days");
        if(cleanupBatchSize<1||cleanupBatchSize>1000)throw new IllegalArgumentException("demo cleanup batch size must be between 1 and 1000");
        this.deliveries=deliveries;this.service=service;this.metrics=metrics;this.targetActive=targetActive;this.staleAfterSeconds=staleAfterSeconds;this.completedRetention=completedRetention;this.cleanupBatchSize=cleanupBatchSize;
        metrics.counter("logitrack.demo.cleanup.deleted");
        metrics.counter("logitrack.demo.cleanup.failures");
        metrics.counter("logitrack.demo.replenishment.failures");
        cleanupMonitorStartedEpochSecond.set(Instant.now().getEpochSecond());
        targetDeliveries.set(targetActive);
        metrics.gauge("logitrack.demo.cleanup.last.success.timestamp.seconds",cleanupLastSuccessEpochSecond);
        metrics.gauge("logitrack.demo.cleanup.monitor.started.timestamp.seconds",cleanupMonitorStartedEpochSecond);
        metrics.gauge("logitrack.demo.active.deliveries",activeDeliveries);
        metrics.gauge("logitrack.demo.target.deliveries",targetDeliveries);
    }

    @Scheduled(initialDelayString="${logitrack.demo.seed-initial-delay-ms:5000}",
        fixedDelayString="${logitrack.demo.seed-delay-ms:60000}")
    public void replenish(){
        try{
            int deleted=deliveries.deleteCompletedDemoBatchBefore(Instant.now().minus(completedRetention),cleanupBatchSize);
            metrics.counter("logitrack.demo.cleanup.deleted").increment(deleted);
            cleanupLastSuccessEpochSecond.set(Instant.now().getEpochSecond());
            if(deleted>0)log.info("Removed {} expired completed demo deliveries",deleted);
        }catch(RuntimeException error){
            metrics.counter("logitrack.demo.cleanup.failures").increment();
            log.warn("Completed demo delivery cleanup failed; replenishment will continue: {}",error.getClass().getSimpleName());
        }
        long active;
        try{
            active=deliveries.countFreshDemoActive(ACTIVE_STATUSES,Instant.now().minusSeconds(staleAfterSeconds));
            activeDeliveries.set(active);
        }catch(RuntimeException error){
            metrics.counter("logitrack.demo.replenishment.failures").increment();
            log.warn("Demo delivery active count failed: {}",error.getClass().getSimpleName());
            return;
        }
        int missing=(int)Math.max(0,targetActive-active);
        for(int index=0;index<missing;index++){
            var route=ROUTES.get((int)((active+index)%ROUTES.size()));
            var token=UUID.randomUUID().toString().substring(0,8);
            var request=new CreateDeliveryRequest("DEMO-"+token,"TRUCK-DEMO-"+token,
                new CreateDeliveryRequest.Location(route.originName(),route.originLat(),route.originLon()),
                new CreateDeliveryRequest.Location(route.destinationName(),route.destinationLat(),route.destinationLon()));
            try{
                service.create(request,"demo-seed-"+token,"demo-seeder-"+Instant.now().toEpochMilli());
            }catch(Exception error){
                metrics.counter("logitrack.demo.replenishment.failures").increment();
                log.warn("Demo delivery replenishment failed: {}",error.getClass().getSimpleName());
            }
        }
        if(missing>0)log.info("Requested {} demo deliveries to restore active target {}",missing,targetActive);
    }

    private record DemoRoute(String originName,double originLat,double originLon,
        String destinationName,double destinationLat,double destinationLon){}
}
