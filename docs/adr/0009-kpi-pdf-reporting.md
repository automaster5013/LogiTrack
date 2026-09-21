# ADR 0009: KPI PDF 보고서 렌더링

## 상태

채택 - 2026-09-19

## 맥락

일별 배송 KPI는 PostgreSQL projection을 source of truth로 사용하고 JSON/CSV로 제공한다. 운영 회의와 외부 공유에는 별도 편집 없이 읽을 수 있는 고품질 문서 형식도 필요하다. 브라우저 화면을 캡처하는 방식은 화면 크기와 렌더링 시점에 따라 결과가 달라지고, 표의 전체 기간을 안정적으로 담기 어렵다.

## 결정

- Spring API가 시작 시 초기화되고 주기적으로 갱신되는 PostgreSQL KPI projection에서 1~90일 범위의 행을 읽는다.
- Python analytics 서비스가 ReportLab으로 A4 가로형 PDF를 생성한다.
- 보고서는 운영 요약, 최근 14일 차트, 전체 일별 상세 표, 데이터 출처, 페이지 번호를 포함한다.
- API는 `GET /api/reports/daily-kpis.pdf?days=30`에서 고정 파일명 attachment로 반환한다.
- 웹 콘솔은 기존 CSV와 함께 PDF 다운로드를 제공한다.

## 결과

PostgreSQL을 단일 지표 원본으로 유지하면서 문서 렌더링 책임은 Python 분석 서비스에 집중된다. PDF 호출에는 서비스 간 요청이 추가되므로 analytics 장애 시 내보내기는 실패하지만, JSON/CSV 조회와 실시간 관제는 영향을 받지 않는다.
