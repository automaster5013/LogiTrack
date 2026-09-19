package io.logitrack.config;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.*;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.bind.MissingRequestHeaderException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.HttpMediaTypeNotSupportedException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import java.time.Instant;
import java.util.NoSuchElementException;

@RestControllerAdvice
public class ApiExceptionHandler {
    @ExceptionHandler(IllegalArgumentException.class) ResponseEntity<ApiError> bad(IllegalArgumentException error,HttpServletRequest request){return response(HttpStatus.BAD_REQUEST,message(error,"Invalid request"),request);}
    @ExceptionHandler(IllegalStateException.class) ResponseEntity<ApiError> conflict(IllegalStateException error,HttpServletRequest request){return response(HttpStatus.CONFLICT,message(error,"Request conflicts with current state"),request);}
    @ExceptionHandler(NoSuchElementException.class) ResponseEntity<ApiError> missing(NoSuchElementException error,HttpServletRequest request){return response(HttpStatus.NOT_FOUND,message(error,"Resource not found"),request);}
    @ExceptionHandler(DataIntegrityViolationException.class) ResponseEntity<ApiError> integrity(DataIntegrityViolationException error,HttpServletRequest request){return response(HttpStatus.CONFLICT,"Resource conflicts with existing data",request);}
    @ExceptionHandler(ObjectOptimisticLockingFailureException.class) ResponseEntity<ApiError> optimisticLock(ObjectOptimisticLockingFailureException error,HttpServletRequest request){return response(HttpStatus.CONFLICT,"Resource was modified by another request",request);}
    @ExceptionHandler(HttpMessageNotReadableException.class) ResponseEntity<ApiError> malformed(HttpMessageNotReadableException error,HttpServletRequest request){return response(HttpStatus.BAD_REQUEST,"Malformed request body",request);}
    @ExceptionHandler({MissingRequestHeaderException.class,MissingServletRequestParameterException.class,MethodArgumentTypeMismatchException.class}) ResponseEntity<ApiError> requestBoundary(Exception error,HttpServletRequest request){return response(HttpStatus.BAD_REQUEST,"Invalid or missing request value",request);}
    @ExceptionHandler(HttpRequestMethodNotSupportedException.class) ResponseEntity<ApiError> method(HttpRequestMethodNotSupportedException error,HttpServletRequest request){return response(HttpStatus.METHOD_NOT_ALLOWED,"Request method is not supported",request);}
    @ExceptionHandler(HttpMediaTypeNotSupportedException.class) ResponseEntity<ApiError> mediaType(HttpMediaTypeNotSupportedException error,HttpServletRequest request){return response(HttpStatus.UNSUPPORTED_MEDIA_TYPE,"Request media type is not supported",request);}
    private ResponseEntity<ApiError> response(HttpStatus status,String message,HttpServletRequest request){return ResponseEntity.status(status).body(new ApiError(message,request.getHeader(RequestTraceFilter.HEADER),Instant.now()));}
    private String message(RuntimeException error,String fallback){return error.getMessage()==null||error.getMessage().isBlank()?fallback:error.getMessage();}
    public record ApiError(String error,String traceId,Instant timestamp) {}
}
