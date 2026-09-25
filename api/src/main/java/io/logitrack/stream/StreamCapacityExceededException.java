package io.logitrack.stream;

public class StreamCapacityExceededException extends RuntimeException {
    public StreamCapacityExceededException(){super("SSE connection capacity has been reached");}
    private StreamCapacityExceededException(String message){super(message);}
    static StreamCapacityExceededException forSubject(){return new StreamCapacityExceededException("SSE connection capacity for this subject has been reached");}
}
