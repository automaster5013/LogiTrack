import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.logitrack.alert.RouteDeviationCalculator;

public final class RouteDeviationFuzzer {
    private static final ObjectMapper MAPPER = new ObjectMapper();

    private RouteDeviationFuzzer() {}

    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        double latitude = data.consumeDouble();
        double longitude = data.consumeDouble();
        try {
            JsonNode geometry = MAPPER.readTree(data.consumeRemainingAsString());
            double distance = RouteDeviationCalculator.distanceMeters(latitude, longitude, geometry);
            if (Double.isNaN(distance) || distance < 0) {
                throw new IllegalStateException("route deviation must be non-negative or positive infinity");
            }
        } catch (JsonProcessingException ignored) {
            // Invalid JSON is an expected request-boundary outcome.
        }
    }
}
