package io.logitrack.delivery;

public record CreateDeliveryRequest(String orderNumber, String vehicleId, Location origin, Location destination) {
    public record Location(String name, double lat, double lon) {}
}

