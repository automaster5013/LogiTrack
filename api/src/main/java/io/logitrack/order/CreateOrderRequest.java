package io.logitrack.order;

public record CreateOrderRequest(String orderNumber, Location origin, Location destination) {
    public record Location(String name, double lat, double lon) {}
}
