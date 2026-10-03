package io.logitrack.order;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import jakarta.persistence.LockModeType;
import java.util.*;

public interface CustomerOrderRepository extends JpaRepository<CustomerOrder, UUID> {
    Optional<CustomerOrder> findByIdempotencyKey(String idempotencyKey);
    Optional<CustomerOrder> findByDispatchRequestKey(String requestKey);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(:key,0))",nativeQuery=true)
    void lockIdempotencyKey(@Param("key") String key);
    @Query(value="SELECT pg_advisory_xact_lock(hashtextextended(concat('order-dispatch:',:key),0))",nativeQuery=true)
    void lockDispatchRequestKey(@Param("key") String key);
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select o from CustomerOrder o where o.id=:id")
    Optional<CustomerOrder> findForUpdateById(UUID id);
}
