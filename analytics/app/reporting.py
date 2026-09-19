from __future__ import annotations

from io import BytesIO
from math import ceil
from typing import Protocol, Sequence

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.pdfgen import canvas


class DailyKpi(Protocol):
    metricDate: object
    totalDeliveries: int
    activeDeliveries: int
    deliveredDeliveries: int
    delayedDeliveries: int
    averageProgressPercent: float
    averageCycleMinutes: float
    onTimeRatePercent: float
    projectedAt: object


INK = colors.HexColor("#10221D")
LIME = colors.HexColor("#B9F227")
PAPER = colors.HexColor("#F3F1E9")
MUTED = colors.HexColor("#66736D")
GRID = colors.HexColor("#D8DDD8")
TOTAL = colors.HexColor("#C8D1CB")
LATE = colors.HexColor("#EF654F")
WHITE = colors.white
PAGE_WIDTH, PAGE_HEIGHT = landscape(A4)
MARGIN = 42
ROWS_PER_PAGE = 30
ROW_HEIGHT = 12


def _text(pdf: canvas.Canvas, value: str, x: float, y: float, size: float = 9,
          color=INK, font: str = "Helvetica") -> None:
    pdf.setFillColor(color)
    pdf.setFont(font, size)
    pdf.drawString(x, y, value)


def _right(pdf: canvas.Canvas, value: str, x: float, y: float, size: float = 9,
           color=INK, font: str = "Helvetica") -> None:
    pdf.setFillColor(color)
    pdf.setFont(font, size)
    pdf.drawRightString(x, y, value)


def _header(pdf: canvas.Canvas, section: str) -> None:
    pdf.setFillColor(INK)
    pdf.rect(0, PAGE_HEIGHT - 72, PAGE_WIDTH, 72, stroke=0, fill=1)
    _text(pdf, "LOGITRACK", MARGIN, PAGE_HEIGHT - 31, 18, LIME, "Helvetica-Bold")
    _text(pdf, "CONTROL TOWER / OPERATIONS INTELLIGENCE", MARGIN, PAGE_HEIGHT - 48, 7.5, WHITE, "Helvetica-Bold")
    _right(pdf, section, PAGE_WIDTH - MARGIN, PAGE_HEIGHT - 39, 9, WHITE, "Helvetica-Bold")


def _footer(pdf: canvas.Canvas, page: int, total_pages: int) -> None:
    pdf.setStrokeColor(GRID)
    pdf.line(MARGIN, 31, PAGE_WIDTH - MARGIN, 31)
    _text(pdf, "Source: PostgreSQL daily KPI projection / UTC cohorts", MARGIN, 17, 7.5, MUTED)
    _right(pdf, f"PAGE {page} / {total_pages}", PAGE_WIDTH - MARGIN, 17, 7.5, MUTED, "Helvetica-Bold")


def _card(pdf: canvas.Canvas, x: float, y: float, width: float, label: str,
          value: str, note: str) -> None:
    pdf.setFillColor(WHITE)
    pdf.setStrokeColor(GRID)
    pdf.roundRect(x, y, width, 70, 4, stroke=1, fill=1)
    _text(pdf, label, x + 14, y + 50, 7.5, MUTED, "Helvetica-Bold")
    _text(pdf, value, x + 14, y + 25, 21, INK, "Helvetica-Bold")
    _right(pdf, note, x + width - 14, y + 27, 7.5, MUTED)


def _summary_page(pdf: canvas.Canvas, rows: Sequence[DailyKpi], page_count: int) -> None:
    _header(pdf, "DAILY DELIVERY KPI REPORT")
    latest = rows[-1] if rows else None
    total_volume = sum(row.totalDeliveries for row in rows)
    total_delivered = sum(row.deliveredDeliveries for row in rows)
    delayed = sum(row.delayedDeliveries for row in rows)
    weighted_on_time = (
        sum(row.onTimeRatePercent * row.deliveredDeliveries for row in rows) / total_delivered
        if total_delivered else 0
    )

    _text(pdf, "EXECUTIVE SNAPSHOT", MARGIN, PAGE_HEIGHT - 104, 8, MUTED, "Helvetica-Bold")
    range_label = "No KPI rows"
    if rows:
        range_label = f"{rows[0].metricDate} TO {rows[-1].metricDate} / {len(rows)} UTC DAYS"
    _text(pdf, range_label, MARGIN, PAGE_HEIGHT - 122, 13, INK, "Helvetica-Bold")
    generated = str(latest.projectedAt)[:19].replace("T", " ") + " UTC" if latest else "Not available"
    _right(pdf, f"PROJECTED {generated}", PAGE_WIDTH - MARGIN, PAGE_HEIGHT - 119, 7.5, MUTED)

    gap = 10
    card_width = (PAGE_WIDTH - 2 * MARGIN - 3 * gap) / 4
    card_y = PAGE_HEIGHT - 212
    _card(pdf, MARGIN, card_y, card_width, "COHORT VOLUME", f"{total_volume:,}", "all created")
    _card(pdf, MARGIN + card_width + gap, card_y, card_width, "DELIVERED", f"{total_delivered:,}", "completed")
    _card(pdf, MARGIN + 2 * (card_width + gap), card_y, card_width, "ON-TIME RATE", f"{weighted_on_time:.1f}%", "weighted")
    _card(pdf, MARGIN + 3 * (card_width + gap), card_y, card_width, "DELAYED", f"{delayed:,}", "current state")

    chart_rows = list(rows[-14:])
    chart_x, chart_y = MARGIN, 78
    chart_w, chart_h = PAGE_WIDTH - 2 * MARGIN, 244
    _text(pdf, "14-DAY DELIVERY VOLUME", chart_x, chart_y + chart_h + 14, 8, MUTED, "Helvetica-Bold")
    pdf.setFillColor(WHITE)
    pdf.setStrokeColor(GRID)
    pdf.roundRect(chart_x, chart_y, chart_w, chart_h, 4, stroke=1, fill=1)
    plot_x, plot_y = chart_x + 38, chart_y + 32
    plot_w, plot_h = chart_w - 58, chart_h - 54
    max_total = max([row.totalDeliveries for row in chart_rows] + [1])
    for tick in range(5):
        y = plot_y + plot_h * tick / 4
        pdf.setStrokeColor(GRID)
        pdf.line(plot_x, y, plot_x + plot_w, y)
        _right(pdf, f"{round(max_total * tick / 4):,}", plot_x - 8, y - 2, 6.5, MUTED)
    if chart_rows:
        slot = plot_w / len(chart_rows)
        bar_width = min(28, slot * .56)
        for index, row in enumerate(chart_rows):
            x = plot_x + slot * index + (slot - bar_width) / 2
            total_h = plot_h * row.totalDeliveries / max_total
            delivered_h = plot_h * row.deliveredDeliveries / max_total
            pdf.setFillColor(TOTAL)
            pdf.rect(x, plot_y, bar_width, total_h, stroke=0, fill=1)
            pdf.setFillColor(INK)
            pdf.rect(x, plot_y, bar_width, delivered_h, stroke=0, fill=1)
            if row.delayedDeliveries:
                pdf.setFillColor(LATE)
                pdf.circle(x + bar_width - 2, plot_y + max(total_h - 3, 3), 3, stroke=0, fill=1)
            date_label = str(row.metricDate)[5:]
            label_w = stringWidth(date_label, "Helvetica", 6.5)
            _text(pdf, date_label, x + (bar_width - label_w) / 2, plot_y - 13, 6.5, MUTED)
    else:
        _text(pdf, "No KPI data available for this period.", plot_x + 20, plot_y + plot_h / 2, 10, MUTED)
    _text(pdf, "TOTAL", chart_x + chart_w - 184, chart_y + chart_h + 14, 7, MUTED, "Helvetica-Bold")
    pdf.setFillColor(TOTAL); pdf.rect(chart_x + chart_w - 201, chart_y + chart_h + 9, 10, 10, stroke=0, fill=1)
    _text(pdf, "DELIVERED", chart_x + chart_w - 107, chart_y + chart_h + 14, 7, MUTED, "Helvetica-Bold")
    pdf.setFillColor(INK); pdf.rect(chart_x + chart_w - 124, chart_y + chart_h + 9, 10, 10, stroke=0, fill=1)
    _text(pdf, "DELAYED", chart_x + chart_w - 30, chart_y + chart_h + 14, 7, MUTED, "Helvetica-Bold")
    pdf.setFillColor(LATE); pdf.circle(chart_x + chart_w - 40, chart_y + chart_h + 14, 4, stroke=0, fill=1)
    _footer(pdf, 1, page_count)


def _detail_page(pdf: canvas.Canvas, rows: Sequence[DailyKpi], page: int, page_count: int) -> None:
    _header(pdf, "DAILY DETAIL")
    _text(pdf, "UTC COHORT DETAIL", MARGIN, PAGE_HEIGHT - 104, 8, MUTED, "Helvetica-Bold")
    _text(pdf, "Operational performance by delivery creation date", MARGIN, PAGE_HEIGHT - 124, 13, INK, "Helvetica-Bold")

    columns = [
        ("DATE", 92, "left"), ("TOTAL", 67, "right"), ("ACTIVE", 67, "right"),
        ("DELIVERED", 82, "right"), ("DELAYED", 72, "right"),
        ("AVG PROGRESS", 112, "right"), ("AVG CYCLE", 96, "right"), ("ON-TIME", 92, "right"),
    ]
    table_x, table_top = MARGIN, PAGE_HEIGHT - 154
    table_width = sum(column[1] for column in columns)
    pdf.setFillColor(INK)
    pdf.rect(table_x, table_top - 24, table_width, 24, stroke=0, fill=1)
    cursor = table_x
    for label, width, align in columns:
        if align == "right":
            _right(pdf, label, cursor + width - 9, table_top - 16, 7, WHITE, "Helvetica-Bold")
        else:
            _text(pdf, label, cursor + 9, table_top - 16, 7, WHITE, "Helvetica-Bold")
        cursor += width

    if not rows:
        _text(pdf, "No KPI data available for this period.", table_x + 9, table_top - 52, 9, MUTED)
    for index, row in enumerate(rows):
        y = table_top - 24 - (index + 1) * ROW_HEIGHT
        pdf.setFillColor(PAPER if index % 2 == 0 else WHITE)
        pdf.rect(table_x, y, table_width, ROW_HEIGHT, stroke=0, fill=1)
        values = [
            str(row.metricDate), f"{row.totalDeliveries:,}", f"{row.activeDeliveries:,}",
            f"{row.deliveredDeliveries:,}", f"{row.delayedDeliveries:,}",
            f"{row.averageProgressPercent:.1f}%", f"{row.averageCycleMinutes:.1f} min",
            f"{row.onTimeRatePercent:.1f}%",
        ]
        cursor = table_x
        for (label, width, align), value in zip(columns, values):
            if align == "right":
                _right(pdf, value, cursor + width - 9, y + 3.25, 6.8, INK)
            else:
                _text(pdf, value, cursor + 9, y + 3.25, 6.8, INK)
            cursor += width
    _footer(pdf, page, page_count)


def render_daily_kpi_report(rows: Sequence[DailyKpi]) -> bytes:
    detail_pages = max(1, ceil(len(rows) / ROWS_PER_PAGE))
    page_count = 1 + detail_pages
    buffer = BytesIO()
    pdf = canvas.Canvas(buffer, pagesize=(PAGE_WIDTH, PAGE_HEIGHT), pageCompression=1)
    pdf.setTitle("LogiTrack Daily Delivery KPI Report")
    pdf.setAuthor("LogiTrack Control Tower")
    pdf.setSubject("PostgreSQL-backed daily delivery KPI report")
    _summary_page(pdf, rows, page_count)
    pdf.showPage()
    for page_index in range(detail_pages):
        start = page_index * ROWS_PER_PAGE
        _detail_page(pdf, rows[start:start + ROWS_PER_PAGE], page_index + 2, page_count)
        if page_index < detail_pages - 1:
            pdf.showPage()
    pdf.save()
    return buffer.getvalue()
