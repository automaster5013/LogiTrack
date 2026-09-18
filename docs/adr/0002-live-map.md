# ADR-0002: 실시간 관제 지도

상태: Accepted — 2026-09-19

## 결정

- 지도 엔진: MapLibre GL JS 6.x
- 기본 벡터 지도: OpenFreeMap Liberty
- 운영 교체점: `NEXT_PUBLIC_MAP_STYLE_URL`
- 동적 데이터: 하나의 GeoJSON source에 차량, 허브, 계획/주행 경로를 함께 갱신

## 이유

MapLibre는 TypeScript 기반 WebGL 벡터 렌더링, 자유로운 스타일 교체, GeoJSON source의 효율적인 실시간 갱신을 제공한다. OpenFreeMap은 API key 없는 로컬 포트폴리오 실행을 가능하게 하며 OpenStreetMap/OpenMapTiles attribution을 유지한다. 상용 운영에서는 MapTiler 등 SLA가 있는 공급자의 style URL로 교체할 수 있다.

## 시각 설계 원칙

- 배경 지도보다 운영 데이터가 우선 보이도록 저채도 basemap과 고대비 lime/ink 색을 사용한다.
- 계획 경로는 점선, 이동 완료 구간은 굵은 실선으로 구분한다.
- 차량은 halo, 본체, label의 3단 계층으로 표현하고 지연 상태는 별도 경고색을 사용한다.
- 선택 배송은 경로 전체가 보이도록 카메라를 맞추고 ETA·진행률을 같은 시선 영역에 둔다.
- 지도 실패 시 관제 데이터 목록은 유지하고 명시적인 degraded 상태를 표시한다.
- attribution은 항상 표시하며 타일 공급자의 사용 조건을 준수한다.

## 배포 주의사항

Next.js/Turbopack에서는 MapLibre worker와 shared module을 `public/maplibre`에 함께 복사해야 한다. standalone Docker 이미지에도 `public/`을 포함한다. 기본 공개 타일은 개발·포트폴리오용이며 실제 상용 트래픽에는 계약된 공급자 또는 자체 호스팅을 사용한다.

