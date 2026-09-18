# ADR 0003: 경로 분석 서비스와 불변 route snapshot

상태: 채택 (2026-09-19)

## 결정

경로 계산은 FastAPI 기반 `analytics` 서비스가 담당한다. OSRM 호환 Route API를 provider 경계로 사용하고, 요청에는 `overview=full`, `geometries=geojson`을 적용한다. 공급자 오류나 시간 초과 시에는 결정론적 geodesic 경로와 보수적인 도로 보정 계수로 즉시 대체한다.

계산 결과는 배송별 불변 `route_snapshots`로 PostgreSQL에 저장한다. geometry, provider, 알고리즘 버전, geometry hash, 거리, 계획 시간과 ETA를 함께 보존한다. 배송 생성 이벤트에도 같은 geometry를 넣어 시뮬레이터, API와 지도 UI가 단일 경로를 공유한다.

## 이유

- 경로 공급자 교체를 배송 command와 분리한다.
- 과거 계획과 실제 운행을 재현하고 알고리즘 변경 영향을 비교할 수 있다.
- 외부 공급자 장애가 배송 생성이나 이벤트 흐름을 중단시키지 않는다.
- 전체 GeoJSON 경로를 사용해 지도 가독성과 차량 위치의 일관성을 높인다.

## 운영 고려사항

기본 개발 설정은 공개 OSRM endpoint를 사용하지만, 공개 demo는 가용성 보장이 없다. 운영 환경에서는 자체 호스팅 OSRM 또는 계약된 호환 공급자의 URL을 `OSRM_BASE_URL`에 설정한다. `ROUTING_PROVIDER=geodesic`은 완전한 오프라인 개발 모드다.

