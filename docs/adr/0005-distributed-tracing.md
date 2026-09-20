# ADR 0005: OTLP와 Tempo 기반 분산 추적

상태: 채택 (2026-09-19)

## 결정

애플리케이션은 vendor-neutral OTLP/HTTP로 trace를 OpenTelemetry Collector에 전송하고 Collector가 OTLP/gRPC로 Tempo에 전달한다. Grafana에는 Tempo datasource를 자동 프로비저닝한다.

- Spring API: Micrometer Tracing의 OpenTelemetry bridge와 OTLP exporter 사용
- Python analytics: FastAPI와 HTTPX 자동 계측, 동일 W3C trace context 전파
- 로컬 개발 sampling: 100%; 운영에서는 `TRACING_SAMPLING_PROBABILITY`로 낮춘다.
- 서비스 이름: `logitrack-control-api`, `logitrack-route-analytics`
- 보존: 로컬 Tempo volume에 24시간

## 이유

API의 배송 생성에서 analytics와 외부 route provider까지 이어지는 latency와 오류를 하나의 trace로 확인할 수 있다. 애플리케이션이 Tempo에 직접 종속되지 않아 이후 다른 OTLP backend나 tail sampling processor로 교체할 수 있다.

## 제한과 후속 작업

Transactional outbox는 이벤트 생성 시점의 W3C trace/span ID와 sampling 결정을 같은 DB transaction에 보존한다. 비동기 publisher는 이를 parent로 복원한 producer span 안에서 Kafka 전송을 수행하므로 Spring Kafka가 주입한 trace header를 통해 downstream consumer까지 하나의 trace로 연결된다. trace가 없는 scheduler·내부 호출은 nullable context로 안전하게 발행한다. 로컬 구성은 암호화하지 않으며 운영 환경의 Collector ingress에는 TLS와 인증을 적용한다.
