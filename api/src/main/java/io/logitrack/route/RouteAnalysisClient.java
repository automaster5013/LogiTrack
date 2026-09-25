package io.logitrack.route;

import io.logitrack.delivery.Delivery;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.util.unit.DataSize;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.*;

@Component
public class RouteAnalysisClient {
    private final RestClient client;
    private final Counter successes;
    private final Counter fallbacks;
    private final ObjectMapper mapper;
    private final int maxResponseBytes;

    public RouteAnalysisClient(RestClient.Builder builder, @Value("${logitrack.analytics.url}") String url,
        @Value("${logitrack.analytics.route-connect-timeout:1s}") Duration connectTimeout,
        @Value("${logitrack.analytics.route-read-timeout:4s}") Duration readTimeout,
        @Value("${logitrack.analytics.route-max-response-size:2MB}") DataSize maxResponseSize,
        ObjectMapper mapper,MeterRegistry metrics) {
        if(connectTimeout.isZero()||connectTimeout.isNegative()||readTimeout.isZero()||readTimeout.isNegative())throw new IllegalArgumentException("Analytics route timeouts must be positive");
        if(maxResponseSize.toBytes()<1024||maxResponseSize.toBytes()>10L*1024*1024)throw new IllegalArgumentException("Analytics route response limit must be between 1KB and 10MB");
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(connectTimeout);
        requestFactory.setReadTimeout(readTimeout);
        client = builder.baseUrl(url).requestFactory(requestFactory).build();
        this.mapper=mapper;this.maxResponseBytes=Math.toIntExact(maxResponseSize.toBytes());
        successes = metrics.counter("logitrack.route.analysis", "outcome", "success");
        fallbacks = metrics.counter("logitrack.route.analysis", "outcome", "fallback");
    }
    public RoutePlan analyze(Delivery delivery) {
        try {
            var request=Map.of(
                "origin",Map.of("lat",delivery.getOriginLat(),"lon",delivery.getOriginLon()),
                "destination",Map.of("lat",delivery.getDestinationLat(),"lon",delivery.getDestinationLon()));
            var body=client.post().uri("/routes/analyze").body(request).exchange((sent,response)->{
                if(!response.getStatusCode().is2xxSuccessful())throw new IllegalStateException("Route analysis failed");
                try(var input=response.getBody()){return input.readNBytes(maxResponseBytes+1);}
            });
            if(body.length>maxResponseBytes)throw new IllegalStateException("Route response is too large");
            var result=mapper.readValue(body,RoutePlan.class);
            if(!valid(result))throw new IllegalStateException("Invalid route response");
            (result.provider().toLowerCase(Locale.ROOT).contains("fallback")?fallbacks:successes).increment();
            return result;
        } catch(Exception ignored) {
            fallbacks.increment();
            return fallback(delivery);
        }
    }
    private boolean valid(RoutePlan result) {
        if(result==null||result.routeId()==null||result.provider()==null||result.provider().isBlank()||result.provider().length()>80||result.algorithmVersion()==null||result.algorithmVersion().isBlank()||result.algorithmVersion().length()>40||result.coordinates()==null||result.coordinates().size()<2||result.coordinates().size()>10_000||result.distanceMeters()<=0||result.durationSeconds()<=0||result.plannedEta()==null||result.geometryHash()==null||result.geometryHash().length()!=64||result.generatedAt()==null||!result.plannedEta().isAfter(result.generatedAt())||result.generatedAt().isAfter(Instant.now().plusSeconds(300)))return false;
        return result.coordinates().stream().allMatch(point->point!=null&&point.size()==2&&point.get(0)!=null&&point.get(1)!=null&&Double.isFinite(point.get(0))&&Double.isFinite(point.get(1))&&point.get(0)>=-180&&point.get(0)<=180&&point.get(1)>=-90&&point.get(1)<=90);
    }
    private RoutePlan fallback(Delivery d) {
        var points=new ArrayList<List<Double>>();
        for(int i=0;i<=24;i++) points.add(List.of(
            d.getOriginLon()+(d.getDestinationLon()-d.getOriginLon())*i/24,
            d.getOriginLat()+(d.getDestinationLat()-d.getOriginLat())*i/24));
        var distance=Math.max(1,Math.round(haversine(d.getOriginLat(),d.getOriginLon(),d.getDestinationLat(),d.getDestinationLon())*1.18));
        var duration=Math.max(60,Math.round(distance/(42_000d/3_600d))); var now=Instant.now();
        return new RoutePlan(UUID.randomUUID(),"spring-fallback","route-v1",points,distance,duration,now.plusSeconds(duration),hash(points),now);
    }
    private long haversine(double lat1,double lon1,double lat2,double lon2) {
        var r=6_371_000d; var dLat=Math.toRadians(lat2-lat1); var dLon=Math.toRadians(lon2-lon1);
        var h=Math.pow(Math.sin(dLat/2),2)+Math.cos(Math.toRadians(lat1))*Math.cos(Math.toRadians(lat2))*Math.pow(Math.sin(dLon/2),2);
        return Math.round(2*r*Math.asin(Math.sqrt(h)));
    }
    private String hash(List<List<Double>> points) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(points.toString().getBytes(StandardCharsets.UTF_8))); }
        catch(Exception e) { throw new IllegalStateException("Could not calculate fallback route hash",e); }
    }
}
