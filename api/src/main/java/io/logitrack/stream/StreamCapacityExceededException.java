package io.logitrack.stream;

public class StreamCapacityExceededException extends RuntimeException {
    public StreamCapacityExceededException(){super("SSE connection capacity has been reached");}
}
