#!/usr/bin/env python3
"""Build the ACAI / ICMR-NIE project brochure PDF (public-facing, no backend detail).

Regenerate with: python3 build_pdf.py   (needs reportlab + Pillow, and the
Liberation fonts at FONT_DIR below). Edit the copy in the section_*()
functions to update content; swap assets/team_shikhar_placeholder.png for a
real photo once one is available and re-run.
"""
import os
from PIL import Image as PILImage

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.colors import HexColor
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase.pdfmetrics import registerFontFamily, stringWidth
from reportlab.platypus import (
    BaseDocTemplate, PageTemplate, Frame, NextPageTemplate, PageBreak,
    Flowable, Paragraph, Spacer, Table, TableStyle, Image as RLImage,
)

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, 'assets')
OUT_PDF = os.path.join(HERE, 'ACAI-ICMR_VRDL_Recommender_System_Brief.pdf')

PAGE_W, PAGE_H = A4
SITE_URL = "https://amity.edu/noida/acai/research-projects.asp"

# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------
FONT_DIR = '/usr/share/fonts/truetype/liberation/'
pdfmetrics.registerFont(TTFont('Sans', FONT_DIR + 'LiberationSans-Regular.ttf'))
pdfmetrics.registerFont(TTFont('Sans-Bold', FONT_DIR + 'LiberationSans-Bold.ttf'))
pdfmetrics.registerFont(TTFont('Sans-Italic', FONT_DIR + 'LiberationSans-Italic.ttf'))
pdfmetrics.registerFont(TTFont('Sans-BoldItalic', FONT_DIR + 'LiberationSans-BoldItalic.ttf'))
pdfmetrics.registerFont(TTFont('Serif', FONT_DIR + 'LiberationSerif-Regular.ttf'))
pdfmetrics.registerFont(TTFont('Serif-Bold', FONT_DIR + 'LiberationSerif-Bold.ttf'))
pdfmetrics.registerFont(TTFont('Serif-Italic', FONT_DIR + 'LiberationSerif-Italic.ttf'))
registerFontFamily('Sans', normal='Sans', bold='Sans-Bold',
                    italic='Sans-Italic', boldItalic='Sans-BoldItalic')
registerFontFamily('Serif', normal='Serif', bold='Serif-Bold',
                    italic='Serif-Italic', boldItalic='Serif-Bold')

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
NAVY = HexColor('#122449')
NAVY_DEEP = HexColor('#0A1830')
GOLD = HexColor('#D9A441')
GOLD_DEEP = HexColor('#B9822A')
MED_BLUE = HexColor('#1565C0')
TEAL = HexColor('#238B7E')
ORANGE = HexColor('#E8622C')
INK = HexColor('#22314A')
MUTED = HexColor('#5B6B82')
FAINT = HexColor('#8C99AD')
LINE = HexColor('#D9E0EA')
PANEL = HexColor('#F3F6FB')
PANEL_ALT = HexColor('#EFF3FB')
CARD_BORDER = HexColor('#E2E8F2')
WHITE = HexColor('#FFFFFF')
CREAM = HexColor('#FBF8F1')

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------
def asset(name):
    return os.path.join(ASSETS, name)


def img_native_size(path):
    with PILImage.open(path) as im:
        return im.size


def img_flowable(path, width=None, height=None):
    iw, ih = img_native_size(path)
    if width and not height:
        height = width * ih / iw
    elif height and not width:
        width = height * iw / ih
    return RLImage(path, width=width, height=height)


def set_line(c, color, width=1.2):
    c.setStrokeColor(color)
    c.setLineWidth(width)
    c.setLineCap(1)
    c.setLineJoin(1)


# ---------------------------------------------------------------------------
# Custom flowables
# ---------------------------------------------------------------------------
class RoundedCard(Flowable):
    """Draws a rounded rectangle behind a content flowable (usually a 1-col Table)."""
    def __init__(self, content, width, bg=WHITE, border=None, border_width=1.0,
                 radius=9, pad=14, top_bar=None, top_bar_h=4):
        Flowable.__init__(self)
        self.content = content
        self.width = width
        self.bg = bg
        self.border = border
        self.border_width = border_width
        self.radius = radius
        self.pad = pad
        self.top_bar = top_bar
        self.top_bar_h = top_bar_h

    def wrap(self, availWidth, availHeight):
        inner_w = self.width - 2 * self.pad
        w, h = self.content.wrap(inner_w, 100000)
        self.content_h = h
        self.height = h + 2 * self.pad
        return (self.width, self.height)

    def draw(self):
        c = self.canv
        if self.bg is not None:
            c.setFillColor(self.bg)
        if self.border is not None:
            c.setStrokeColor(self.border)
            c.setLineWidth(self.border_width)
        c.roundRect(0, 0, self.width, self.height, self.radius,
                    fill=1 if self.bg is not None else 0,
                    stroke=1 if self.border is not None else 0)
        if self.top_bar is not None:
            c.setFillColor(self.top_bar)
            c.roundRect(0, self.height - self.top_bar_h, self.width, self.top_bar_h,
                        self.top_bar_h / 2, fill=1, stroke=0)
            # square off the bottom of the bar so it reads as a straight accent
            c.rect(0, self.height - self.top_bar_h, self.width, self.top_bar_h / 2, fill=1, stroke=0)
        self.content.drawOn(c, self.pad, self.pad)


def vstack(items, width, gaps=None, default_gap=4):
    """Stack flowables in a single borderless column with per-item bottom gaps."""
    n = len(items)
    if gaps is None:
        gaps = [default_gap] * n
    style = [
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
    ]
    for i, g in enumerate(gaps):
        if i < n - 1 and g:
            style.append(('BOTTOMPADDING', (0, i), (0, i), g))
    t = Table([[it] for it in items], colWidths=[width])
    t.setStyle(TableStyle(style))
    return t


def row(cards, col_widths, gap=12, valign='TOP'):
    """Lay flowables side by side with a fixed gap between columns."""
    n = len(cards)
    style = [
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('VALIGN', (0, 0), (-1, -1), valign),
    ]
    for i in range(n - 1):
        style.append(('RIGHTPADDING', (i, 0), (i, 0), gap))
    t = Table([cards], colWidths=col_widths)
    t.setStyle(TableStyle(style))
    return t


class IconIndicator(Flowable):
    """A filled circle with a simple monoline glyph — used as small inline icons."""
    def __init__(self, kind, d=34, bg=NAVY, fg=WHITE):
        Flowable.__init__(self)
        self.kind = kind
        self.d = d
        self.bg = bg
        self.fg = fg

    def wrap(self, aW, aH):
        return (self.d, self.d)

    def draw(self):
        c = self.canv
        r = self.d / 2
        c.setFillColor(self.bg)
        c.circle(r, r, r, fill=1, stroke=0)
        draw_glyph(c, self.kind, r, r, r * 0.52, self.fg)


# ---------------------------------------------------------------------------
# Glyph drawing (simple monoline icons drawn with primitive shapes)
# ---------------------------------------------------------------------------
def draw_glyph(c, kind, cx, cy, r, color):
    c.saveState()
    set_line(c, color, max(1.3, r * 0.14))
    c.setFillColor(color)
    if kind == 'intake':
        w, h = r * 1.15, r * 1.5
        x0, y0 = cx - w / 2, cy - h / 2
        c.roundRect(x0, y0, w, h, 2, fill=0, stroke=1)
        for i in range(3):
            ly = y0 + h * 0.72 - i * h * 0.26
            c.line(x0 + w * 0.2, ly, x0 + w * 0.8, ly)
    elif kind == 'feature':
        pts = [(cx, cy + r * 0.85), (cx - r * 0.8, cy - r * 0.5), (cx + r * 0.8, cy - r * 0.5)]
        for i in range(3):
            for j in range(i + 1, 3):
                c.line(pts[i][0], pts[i][1], pts[j][0], pts[j][1])
        for (px, py) in pts:
            c.circle(px, py, r * 0.16, fill=1, stroke=0)
    elif kind == 'ai':
        rad = r * 0.85
        p = c.beginPath()
        for i in range(6):
            import math
            ang = math.pi / 3 * i - math.pi / 2
            x, y = cx + rad * math.cos(ang), cy + rad * math.sin(ang)
            if i == 0:
                p.moveTo(x, y)
            else:
                p.lineTo(x, y)
        p.close()
        c.drawPath(p, fill=0, stroke=1)
        c.circle(cx, cy, r * 0.22, fill=1, stroke=0)
    elif kind == 'check':
        c.circle(cx, cy, r * 0.92, fill=0, stroke=1)
        p = c.beginPath()
        p.moveTo(cx - r * 0.42, cy - r * 0.03)
        p.lineTo(cx - r * 0.1, cy - r * 0.38)
        p.lineTo(cx + r * 0.48, cy + r * 0.35)
        c.drawPath(p, fill=0, stroke=1)
    elif kind == 'lab':
        neck_w = r * 0.34
        c.line(cx - neck_w / 2, cy + r * 0.9, cx - neck_w / 2, cy + r * 0.15)
        c.line(cx + neck_w / 2, cy + r * 0.9, cx + neck_w / 2, cy + r * 0.15)
        c.line(cx - neck_w * 0.9, cy + r * 0.9, cx + neck_w * 0.9, cy + r * 0.9)
        p = c.beginPath()
        p.moveTo(cx - neck_w / 2, cy + r * 0.15)
        p.lineTo(cx - r * 0.85, cy - r * 0.8)
        p.lineTo(cx + r * 0.85, cy - r * 0.8)
        p.lineTo(cx + neck_w / 2, cy + r * 0.15)
        p.close()
        c.drawPath(p, fill=0, stroke=1)
        c.setFillColor(color)
        c.rect(cx - r * 0.6, cy - r * 0.72, r * 1.2, r * 0.34, fill=1, stroke=0)
    elif kind == 'loop':
        c.arc(cx - r * 0.8, cy - r * 0.8, cx + r * 0.8, cy + r * 0.8, 40, 280)
        import math
        ang = math.radians(40)
        ax, ay = cx + r * 0.8 * math.cos(ang), cy + r * 0.8 * math.sin(ang)
        c.setFillColor(color)
        p = c.beginPath()
        p.moveTo(ax, ay)
        p.lineTo(ax - r * 0.32, ay + r * 0.05)
        p.lineTo(ax - r * 0.06, ay + r * 0.34)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
    elif kind == 'globe':
        c.circle(cx, cy, r * 0.9, fill=0, stroke=1)
        from reportlab.lib.units import mm as _mm
        c.ellipse(cx - r * 0.42, cy - r * 0.9, cx + r * 0.42, cy + r * 0.9, fill=0, stroke=1)
        c.line(cx - r * 0.9, cy, cx + r * 0.9, cy)
        c.line(cx - r * 0.78, cy + r * 0.42, cx + r * 0.78, cy + r * 0.42)
        c.line(cx - r * 0.78, cy - r * 0.42, cx + r * 0.78, cy - r * 0.42)
    elif kind == 'shield':
        p = c.beginPath()
        p.moveTo(cx, cy + r * 0.95)
        p.curveTo(cx + r * 0.85, cy + r * 0.7, cx + r * 0.85, cy + r * 0.2, cx + r * 0.85, cy - r * 0.1)
        p.curveTo(cx + r * 0.85, cy - r * 0.65, cx + r * 0.4, cy - r * 0.95, cx, cy - r * 1.05)
        p.curveTo(cx - r * 0.4, cy - r * 0.95, cx - r * 0.85, cy - r * 0.65, cx - r * 0.85, cy - r * 0.1)
        p.curveTo(cx - r * 0.85, cy + r * 0.2, cx - r * 0.85, cy + r * 0.7, cx, cy + r * 0.95)
        p.close()
        c.drawPath(p, fill=0, stroke=1)
    c.restoreState()


# ---------------------------------------------------------------------------
# Process flow diagram flowable
# ---------------------------------------------------------------------------
class ProcessFlow(Flowable):
    def __init__(self, steps, icon_d=46, band_h=112):
        Flowable.__init__(self)
        self.steps = steps
        self.icon_d = icon_d
        self.band_h = band_h
        self.width = 0

    def wrap(self, availWidth, availHeight):
        self.width = availWidth
        return (availWidth, self.band_h)

    def draw(self):
        c = self.canv
        n = len(self.steps)
        col_w = self.width / n
        cy = self.band_h - self.icon_d / 2 - 8
        r = self.icon_d / 2

        for i, step in enumerate(self.steps):
            cx = col_w * i + col_w / 2
            if i < n - 1:
                nx = col_w * (i + 1) + col_w / 2
                set_line(c, FAINT, 1.3)
                c.line(cx + r + 3, cy, nx - r - 8, cy)
                c.setFillColor(FAINT)
                p = c.beginPath()
                p.moveTo(nx - r - 8, cy + 3.6)
                p.lineTo(nx - r - 2, cy)
                p.lineTo(nx - r - 8, cy - 3.6)
                p.close()
                c.drawPath(p, fill=1, stroke=0)

            c.setFillColor(NAVY)
            c.circle(cx, cy, r, fill=1, stroke=0)
            draw_glyph(c, step['icon'], cx, cy, r * 0.56, WHITE)

            # step number badge
            c.setFillColor(GOLD)
            c.circle(cx + r * 0.72, cy + r * 0.72, 8.2, fill=1, stroke=0)
            c.setFillColor(NAVY_DEEP)
            c.setFont('Sans-Bold', 8.2)
            c.drawCentredString(cx + r * 0.72, cy + r * 0.72 - 2.9, str(i + 1))

            # label (up to two lines) below the circle
            c.setFillColor(INK)
            c.setFont('Sans-Bold', 8.6)
            words = step['label'].split(' ')
            lines, cur = [], ''
            maxw = col_w - 6
            for wd in words:
                trial = (cur + ' ' + wd).strip()
                if stringWidth(trial, 'Sans-Bold', 8.6) <= maxw:
                    cur = trial
                else:
                    if cur:
                        lines.append(cur)
                    cur = wd
            if cur:
                lines.append(cur)
            ly = cy - r - 15
            for ln in lines:
                c.drawCentredString(cx, ly, ln)
                ly -= 10.4


# ---------------------------------------------------------------------------
# Paragraph styles
# ---------------------------------------------------------------------------
styles = {
    'kicker': ParagraphStyle('kicker', fontName='Sans-Bold', fontSize=9.3, leading=11,
                              textColor=GOLD_DEEP, spaceAfter=4),
    'kicker_white': ParagraphStyle('kicker_white', fontName='Sans-Bold', fontSize=9.3, leading=11,
                                    textColor=GOLD, spaceAfter=4),
    'h1': ParagraphStyle('h1', fontName='Serif-Bold', fontSize=21, leading=25,
                          textColor=NAVY, spaceAfter=10),
    'h1_white': ParagraphStyle('h1_white', fontName='Serif-Bold', fontSize=27, leading=32,
                                textColor=WHITE, spaceAfter=8),
    'subtitle_white': ParagraphStyle('subtitle_white', fontName='Sans', fontSize=12.5, leading=17,
                                      textColor=HexColor('#CBD8ED'), spaceAfter=0),
    'lead': ParagraphStyle('lead', fontName='Sans', fontSize=10.6, leading=16.4,
                            textColor=INK, spaceAfter=9, alignment=TA_JUSTIFY),
    'body': ParagraphStyle('body', fontName='Sans', fontSize=9.6, leading=14.2,
                            textColor=INK, spaceAfter=6, alignment=TA_JUSTIFY),
    'body_left': ParagraphStyle('body_left', fontName='Sans', fontSize=9.6, leading=14.2,
                                 textColor=INK, spaceAfter=6, alignment=TA_LEFT),
    'card_h': ParagraphStyle('card_h', fontName='Sans-Bold', fontSize=11, leading=13.5,
                              textColor=NAVY, spaceAfter=3),
    'card_b': ParagraphStyle('card_b', fontName='Sans', fontSize=8.9, leading=12.6,
                              textColor=MUTED, spaceAfter=0),
    'stat_num': ParagraphStyle('stat_num', fontName='Serif-Bold', fontSize=25, leading=27,
                                textColor=NAVY, alignment=TA_CENTER, spaceAfter=1),
    'stat_lbl': ParagraphStyle('stat_lbl', fontName='Sans-Bold', fontSize=8.1, leading=10.4,
                                textColor=MUTED, alignment=TA_CENTER),
    'legend_num': ParagraphStyle('legend_num', fontName='Serif-Bold', fontSize=11, leading=13,
                                  textColor=GOLD_DEEP),
    'legend_h': ParagraphStyle('legend_h', fontName='Sans-Bold', fontSize=10, leading=13,
                                textColor=NAVY, spaceAfter=2),
    'legend_b': ParagraphStyle('legend_b', fontName='Sans', fontSize=9.2, leading=13.4,
                                textColor=INK, alignment=TA_JUSTIFY),
    'team_name': ParagraphStyle('team_name', fontName='Sans-Bold', fontSize=10.3, leading=12.6,
                                 textColor=NAVY, alignment=TA_CENTER, spaceAfter=1),
    'team_role': ParagraphStyle('team_role', fontName='Sans-Italic', fontSize=8.5, leading=11,
                                 textColor=MUTED, alignment=TA_CENTER),
    'group_lbl': ParagraphStyle('group_lbl', fontName='Sans-Bold', fontSize=9.4, leading=12,
                                 textColor=WHITE, alignment=TA_CENTER),
    'callout_h': ParagraphStyle('callout_h', fontName='Sans-Bold', fontSize=11.3, leading=14,
                                 textColor=WHITE, spaceAfter=3),
    'callout_b': ParagraphStyle('callout_b', fontName='Sans', fontSize=9.4, leading=13.6,
                                 textColor=HexColor('#DCE6F5')),
    'partner_h': ParagraphStyle('partner_h', fontName='Sans-Bold', fontSize=10.6, leading=13.4,
                                 textColor=NAVY, spaceAfter=3, alignment=TA_CENTER),
    'partner_b': ParagraphStyle('partner_b', fontName='Sans', fontSize=9, leading=12.8,
                                 textColor=MUTED, alignment=TA_CENTER),
    'foot_tag': ParagraphStyle('foot_tag', fontName='Sans-Bold', fontSize=8, leading=10,
                                textColor=MUTED),
    'link_row': ParagraphStyle('link_row', fontName='Sans-Bold', fontSize=9, leading=12,
                                textColor=HexColor('#CBD8ED'), alignment=TA_CENTER),
}


# ---------------------------------------------------------------------------
# Layout helpers built on the styles/flowables above
# ---------------------------------------------------------------------------
def vstack(items, width, gaps=None, default_gap=4, align='LEFT'):
    n = len(items)
    if gaps is None:
        gaps = [default_gap] * n
    style = [
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('ALIGN', (0, 0), (-1, -1), align),
    ]
    for i, g in enumerate(gaps):
        if i < n - 1 and g:
            style.append(('BOTTOMPADDING', (0, i), (0, i), g))
    t = Table([[it] for it in items], colWidths=[width])
    t.setStyle(TableStyle(style))
    return t


def row(cards, col_widths, gap=12, valign='TOP', align='CENTER'):
    n = len(cards)
    style = [
        ('LEFTPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0),
        ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('VALIGN', (0, 0), (-1, -1), valign),
        ('ALIGN', (0, 0), (-1, -1), align),
    ]
    for i in range(n - 1):
        style.append(('RIGHTPADDING', (i, 0), (i, 0), gap))
    t = Table([cards], colWidths=col_widths)
    t.setStyle(TableStyle(style))
    return t


def center(flowable, width):
    t = Table([[flowable]], colWidths=[width])
    t.setStyle(TableStyle([
        ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0), ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
    ]))
    return t


def wrap_text(text, font, size, max_width):
    words = text.split()
    lines, cur = [], ''
    for w in words:
        trial = (cur + ' ' + w).strip()
        if stringWidth(trial, font, size) <= max_width:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def draw_logo(c, path, x, y, height=None, width=None, right=None):
    iw, ih = img_native_size(path)
    if height and not width:
        width = height * iw / ih
    elif width and not height:
        height = width * ih / iw
    if right is not None:
        x = right - width
    c.drawImage(path, x, y, width=width, height=height,
                preserveAspectRatio=True, mask='auto')
    return width, height


def draw_network_deco(c, cx, cy, size, alpha=0.14, color=NAVY, seed=9):
    import random
    random.seed(seed)
    c.saveState()
    c.setFillAlpha(alpha)
    c.setStrokeAlpha(alpha)
    set_line(c, color, 1.1)
    pts = []
    for i in range(13):
        ang = random.uniform(0, 6.283)
        rad = random.uniform(0.25, 0.85) * size
        pts.append((cx + rad * __import__('math').cos(ang),
                    cy + rad * 0.8 * __import__('math').sin(ang)))
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            x1, y1 = pts[i]
            x2, y2 = pts[j]
            if ((x1 - x2) ** 2 + (y1 - y2) ** 2) ** 0.5 < size * 0.62:
                c.line(x1, y1, x2, y2)
    c.setFillColor(color)
    for (x, y) in pts:
        c.circle(x, y, 2.1, fill=1, stroke=0)
    c.restoreState()


# ---------------------------------------------------------------------------
# Cover page (fully custom canvas drawing)
# ---------------------------------------------------------------------------
def draw_cover(c, doc):
    c.saveState()
    M = 46
    c.setFillColor(WHITE)
    c.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)

    top_y = PAGE_H - 40 - 34
    draw_logo(c, asset('amity_full_logo.png'), M, top_y, height=34)
    draw_logo(c, asset('icmr_nie_logo.png'), None, top_y + 3, height=28, right=PAGE_W - M)

    set_line(c, LINE, 1)
    c.line(M, PAGE_H - 96, PAGE_W - M, PAGE_H - 96)

    c.setFillColor(GOLD_DEEP)
    c.setFont('Sans-Bold', 10)
    c.drawString(M, PAGE_H - 122, "AI-POWERED CLINICAL DECISION SUPPORT  •  RESEARCH PROJECT BRIEF")

    title = ("Personalized Recommender System for Virus Research "
             "& Diagnosis Laboratory Network")
    lines = wrap_text(title, 'Serif-Bold', 26, PAGE_W - 2 * M - 4)
    y = PAGE_H - 158
    c.setFillColor(NAVY)
    c.setFont('Serif-Bold', 26)
    for ln in lines:
        c.drawString(M, y, ln)
        y -= 31

    y -= 8
    c.setFont('Sans', 13.5)
    c.setFillColor(MUTED)
    for ln in wrap_text("Advancing Diagnostic Decision-Making through Artificial Intelligence",
                        'Sans', 13.5, PAGE_W - 2 * M - 4):
        y -= 19
        c.drawString(M, y, ln)

    y -= 30
    set_line(c, GOLD, 2.4)
    c.line(M, y, M + 46, y)
    y -= 18
    c.setFont('Sans-Bold', 10.4)
    c.setFillColor(NAVY)
    c.drawString(M, y, "Amity Centre for Artificial Intelligence, Amity University, Noida, India")
    y -= 15
    c.setFont('Sans', 9.5)
    c.setFillColor(MUTED)
    c.drawString(M, y, "In partnership with ICMR – National Institute of Epidemiology, supported by the")
    y -= 13
    c.drawString(M, y, "Department of Health Research, Ministry of Health & Family Welfare, Government of India")

    # --- bottom navy band ---
    band_h = 168

    # decorative graphic fills the open space between the text block and the band
    gap_top, gap_bottom = y - 24, band_h + 26
    draw_network_deco(c, PAGE_W * 0.585, (gap_top + gap_bottom) / 2,
                       min(150, (gap_top - gap_bottom) / 2 + 40), alpha=0.11)

    c.setFillColor(NAVY_DEEP)
    c.rect(0, 0, PAGE_W, band_h, fill=1, stroke=0)
    set_line(c, GOLD, 2)
    c.line(0, band_h, PAGE_W, band_h)

    c.setFillColor(GOLD)
    c.setFont('Sans-Bold', 10.6)
    c.drawCentredString(PAGE_W / 2, band_h - 32,
                         "PROJECT SUPPORTED BY THE INDIAN COUNCIL OF MEDICAL RESEARCH (ICMR)")

    set_line(c, HexColor('#26385F'), 1)
    c.line(M, band_h - 52, PAGE_W - M, band_h - 52)

    c.setFont('Sans', 8.6)
    c.setFillColor(HexColor('#9FB2D6'))
    c.drawCentredString(PAGE_W / 2, band_h - 70, "JUMP TO")

    jump = [('Project Overview', 'sec_overview'), ('Methodology', 'sec_method'),
            ('Scope & Impact', 'sec_scope'), ('Partnership', 'sec_partner'),
            ('Project Team', 'sec_team')]
    c.setFont('Sans-Bold', 9.3)
    gap = 16
    widths = [stringWidth(t, 'Sans-Bold', 9.3) for t, _ in jump]
    total = sum(widths) + gap * (len(jump) - 1)
    x = (PAGE_W - total) / 2
    ly = band_h - 92
    for (t, key), w in zip(jump, widths):
        c.setFillColor(HexColor('#D7E2F5'))
        c.drawString(x, ly, t)
        c.linkAbsolute('', key, (x - 3, ly - 4, x + w + 3, ly + 11), thickness=0)
        x += w + gap

    c.setFont('Sans', 8.6)
    c.setFillColor(HexColor('#7E93BC'))
    url_label = SITE_URL.replace('https://', '')
    c.drawCentredString(PAGE_W / 2, 26, url_label)
    uw = stringWidth(url_label, 'Sans', 8.6)
    c.linkURL(SITE_URL, (PAGE_W / 2 - uw / 2 - 6, 18, PAGE_W / 2 + uw / 2 + 6, 34), relative=0)

    c.restoreState()


# ---------------------------------------------------------------------------
# Inner page chrome (header / footer / bookmarks)
# ---------------------------------------------------------------------------
SECTION_BY_PAGE = {
    2: ("PROJECT OVERVIEW", 'sec_overview', 'Project Overview'),
    3: ("METHODOLOGY", 'sec_method', 'Methodology'),
    4: ("SCOPE & IMPACT", 'sec_scope', 'Scope & Impact'),
    5: ("INSTITUTIONAL PARTNERSHIP", 'sec_partner', 'Institutional Partnership'),
    6: ("PROJECT TEAM", 'sec_team', 'Project Team'),
}


def draw_inner(c, doc):
    c.saveState()
    M = 46
    page = doc.page
    label, key, outline_title = SECTION_BY_PAGE.get(page, ("", None, None))
    if key:
        c.bookmarkPage(key)
        c.addOutlineEntry(outline_title, key, level=0, closed=0)

    c.setFont('Sans-Bold', 7.6)
    c.setFillColor(MUTED)
    c.drawString(M, PAGE_H - 40, "AMITY CENTRE FOR ARTIFICIAL INTELLIGENCE  ·  ICMR – NIE")
    c.setFont('Sans-Bold', 7.6)
    c.setFillColor(GOLD_DEEP)
    c.drawRightString(PAGE_W - M, PAGE_H - 40, label)
    set_line(c, LINE, 1)
    c.line(M, PAGE_H - 48, PAGE_W - M, PAGE_H - 48)

    set_line(c, LINE, 1)
    c.line(M, 46, PAGE_W - M, 46)
    c.setFont('Sans-Italic', 7.8)
    c.setFillColor(FAINT)
    c.drawString(M, 32, "Personalized Recommender System for Virus Research & Diagnosis Laboratory Network")
    c.setFont('Sans-Bold', 8)
    c.setFillColor(MUTED)
    c.drawRightString(PAGE_W - M, 32, str(doc.page))

    c.restoreState()


# ---------------------------------------------------------------------------
# Section content builders
# ---------------------------------------------------------------------------
def section_overview(W):
    items = []
    items.append(Paragraph('PROJECT OVERVIEW', styles['kicker']))
    items.append(Paragraph('Turning Clinical Symptoms into Faster, Smarter Diagnostic Decisions', styles['h1']))

    lead1 = ("India's public-health laboratories and frontline clinicians confront an unusually broad and "
             "constantly shifting spectrum of viral and infectious pathogens. When a patient presents with "
             "fever, respiratory distress, or a neurological syndrome, deciding which of dozens of possible "
             "laboratory tests to prioritise is a time-critical judgement call — one that shapes how quickly "
             "a patient is diagnosed and how efficiently a laboratory's testing capacity is used.")
    lead2 = ("This project, undertaken by the Amity Centre for Artificial Intelligence in partnership with "
             "ICMR – National Institute of Epidemiology, develops an AI-based clinical decision-support "
             "system that turns a patient's demographic profile, clinical symptoms and syndromic presentation "
             "into a ranked, confidence-scored shortlist of the most probable infections — guiding the "
             "clinician toward the most relevant confirmatory laboratory test at the point of care.")
    items.append(Paragraph(lead1, styles['lead']))
    items.append(Paragraph(lead2, styles['lead']))
    items.append(Spacer(1, 4))

    callout_content = vstack([
        Paragraph('DESIGNED TO SUPPORT, NOT REPLACE, CLINICAL JUDGEMENT',
                  ParagraphStyle('co_h', fontName='Sans-Bold', fontSize=9.6, textColor=GOLD, leading=12)),
        Paragraph('Every recommendation is reviewed by a treating physician and validated against confirmed '
                  'laboratory results before it informs patient care.', styles['callout_b']),
    ], W - 28, gaps=[4])
    items.append(RoundedCard(callout_content, W, bg=NAVY, pad=14, radius=10))
    items.append(Spacer(1, 16))

    items.append(Paragraph('PROJECT OBJECTIVES', styles['kicker']))
    items.append(Spacer(1, 2))

    obj_data = [
        ('intake', 'Smart Infection Triage',
         "Analyse patient demographics, symptoms and syndromic presentation to recommend the most probable "
         "infections and prioritise the right laboratory tests."),
        ('feature', 'Rigorous Model Optimisation',
         "Benchmark and refine multiple modelling approaches to maximise diagnostic accuracy and consistency "
         "with recognised clinical syndrome definitions."),
        ('check', 'Human-in-the-Loop Validation',
         "Close the loop between AI recommendations, clinician review and confirmed laboratory results, so "
         "every case strengthens the system over time."),
        ('globe', 'Surveillance & Outbreak Intelligence',
         "Lay the groundwork to surface geographic and seasonal infection patterns across ICMR's national "
         "surveillance network, supporting early outbreak signal detection."),
    ]
    gap = 14
    col_w = (W - gap) / 2
    cards = []
    for icon, h, b in obj_data:
        content = vstack([
            IconIndicator(icon, d=32, bg=MED_BLUE),
            Paragraph(h, styles['card_h']),
            Paragraph(b, styles['card_b']),
        ], col_w - 28, gaps=[7, 4])
        cards.append(RoundedCard(content, col_w, bg=PANEL, pad=14, radius=9))
    grid = Table([[cards[0], cards[1]], [cards[2], cards[3]]], colWidths=[col_w, col_w])
    grid.setStyle(TableStyle([
        ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0), ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('VALIGN', (0, 0), (-1, -1), 'TOP'),
        ('RIGHTPADDING', (0, 0), (0, -1), gap),
        ('BOTTOMPADDING', (0, 0), (-1, 0), gap),
    ]))
    items.append(grid)
    return items


def section_methodology(W):
    items = []
    items.append(Paragraph('METHODOLOGY', styles['kicker']))
    items.append(Paragraph('From Symptom to Recommendation: How the System Works', styles['h1']))
    items.append(Paragraph(
        "Each case moves through a structured, six-stage pipeline that pairs rich clinical data with a "
        "purpose-built AI model — and feeds confirmed outcomes back into the system.", styles['lead']))
    items.append(Spacer(1, 8))

    steps = [
        {'icon': 'intake', 'label': 'Clinical Intake'},
        {'icon': 'feature', 'label': 'Feature Engineering'},
        {'icon': 'ai', 'label': 'AI Classification'},
        {'icon': 'check', 'label': 'Syndrome Check'},
        {'icon': 'lab', 'label': 'Clinician & Lab Review'},
        {'icon': 'loop', 'label': 'Continuous Learning'},
    ]
    diagram_content = ProcessFlow(steps, icon_d=44, band_h=100)
    items.append(RoundedCard(diagram_content, W, bg=PANEL, pad=14, radius=10))
    items.append(Spacer(1, 18))

    legend = [
        ('1', 'Clinical Intake',
         "Patient demographics, geographic details and a structured checklist of 35 symptom indicators across "
         "neurological, respiratory, gastrointestinal, dermatological and systemic presentations are captured "
         "at the point of care."),
        ('2', 'Feature Engineering',
         "Clinical, geographic (state / district) and temporal (seasonality, illness duration) signals are "
         "combined into a single structured patient profile."),
        ('3', 'AI Classification',
         "A purpose-built, dual-stage deep-learning model first narrows to the most probable major infection "
         "group, then resolves closely related sub-types — each with a calibrated confidence score."),
        ('4', 'Syndrome Check',
         "Recommendations are automatically cross-checked against the reported clinical syndrome, filtering "
         "out results inconsistent with the clinical picture before they reach the clinician."),
        ('5', 'Clinician & Lab Review',
         "The treating physician reviews the ranked recommendations; once confirmatory laboratory results are "
         "available, they are recorded against the case."),
        ('6', 'Continuous Learning',
         "Confirmed outcomes flow back into ongoing model evaluation, so the system keeps improving with "
         "every case."),
    ]
    legend_rows = []
    for num, h, b in legend:
        num_cell = Paragraph(num, styles['legend_num'])
        text_cell = vstack([Paragraph(h, styles['legend_h']), Paragraph(b, styles['legend_b'])],
                            W - 22 - 14, gaps=[1])
        legend_rows.append(row([num_cell, text_cell], [22, W - 22 - 14], gap=14, valign='TOP', align='LEFT'))
    items.append(vstack(legend_rows, W, gaps=[11] * (len(legend_rows) - 1) + [0]))
    items.append(Spacer(1, 18))

    callout_content = vstack([
        Paragraph('TRANSPARENT BY DESIGN',
                  ParagraphStyle('co3', fontName='Sans-Bold', fontSize=9.6, textColor=GOLD, leading=12)),
        Paragraph("Every recommendation carries a calibrated confidence score alongside its leading "
                  "alternatives, so the clinician always sees the model's reasoning — never a single, "
                  "unexplained answer.", styles['callout_b']),
    ], W - 28, gaps=[4])
    items.append(RoundedCard(callout_content, W, bg=NAVY, pad=14, radius=10))
    return items


def section_scope(W):
    items = []
    items.append(Paragraph('SCOPE &amp; COVERAGE', styles['kicker']))
    items.append(Paragraph("Built on One of India's Richest Clinical Surveillance Datasets", styles['h1']))
    items.append(Paragraph(
        "The system is trained and continuously evaluated on real-world clinical data contributed through "
        "ICMR's national surveillance network — giving it a breadth of coverage few diagnostic "
        "decision-support tools can match.", styles['lead']))
    items.append(Spacer(1, 6))

    stats = [
        ('24', 'Major infection<br/>categories'),
        ('35', 'Structured clinical<br/>symptom indicators'),
        ('9', 'Recognised<br/>syndromic categories'),
        ('663K+', 'Curated clinical cases<br/>in the training corpus'),
        ('100', 'Pathogens in the<br/>confirmatory reference panel'),
        ('35+', 'States &amp; union<br/>territories represented'),
    ]
    gap = 12
    col_w = (W - 2 * gap) / 3
    tiles = []
    for num, lbl in stats:
        content = vstack([
            Paragraph(num, styles['stat_num']),
            Paragraph(lbl, styles['stat_lbl']),
        ], col_w - 20, gaps=[3], align='CENTER')
        tiles.append(RoundedCard(content, col_w, bg=PANEL_ALT, pad=12, radius=9))
    grid = Table([tiles[0:3], tiles[3:6]], colWidths=[col_w] * 3)
    grid.setStyle(TableStyle([
        ('LEFTPADDING', (0, 0), (-1, -1), 0), ('RIGHTPADDING', (0, 0), (-1, -1), 0),
        ('TOPPADDING', (0, 0), (-1, -1), 0), ('BOTTOMPADDING', (0, 0), (-1, -1), 0),
        ('RIGHTPADDING', (0, 0), (1, -1), gap),
        ('BOTTOMPADDING', (0, 0), (-1, 0), gap),
    ]))
    items.append(grid)
    items.append(Spacer(1, 16))

    items.append(Paragraph(
        "Recommendations span globally significant pathogens — including Dengue, Chikungunya, Japanese "
        "Encephalitis, Hepatitis A/B/C/E, Influenza A and B subtypes (H1N1, H3N2, Victoria), SARS-CoV-2, "
        "Respiratory Syncytial Virus and more — with a further refinement layer resolving additional "
        "sub-types (including Zika, West Nile virus and Kyasanur Forest Disease) within the broader ‘other "
        "viral infections’ group. Every recommendation is cross-referenced against ICMR's curated national "
        "reference panel of confirmatory laboratory tests, keeping the tool aligned with what laboratories "
        "can practically confirm.", styles['body']))
    items.append(Spacer(1, 8))

    callout_content = vstack([
        Paragraph('CLOSING THE LOOP — FROM PREDICTION TO CONFIRMED DIAGNOSIS',
                  ParagraphStyle('co2', fontName='Sans-Bold', fontSize=9.6, textColor=GOLD, leading=12)),
        Paragraph("Unlike a one-way prediction tool, the system tracks each case from initial AI recommendation "
                  "through clinician review to confirmed laboratory outcome — building a continuously "
                  "growing, ground-truthed evidence base for future refinement.", styles['callout_b']),
    ], W - 28, gaps=[4])
    items.append(RoundedCard(callout_content, W, bg=NAVY, pad=14, radius=10))
    items.append(Spacer(1, 12))

    note_style = ParagraphStyle('note', fontName='Sans-Italic', fontSize=8.8, textColor=MUTED, leading=12.6)
    gap2 = 20
    note_w = (W - gap2) / 2
    notes = row([
        Paragraph("<b>Roadmap.</b> Extending this evidence base to surface geographic and seasonal "
                  "outbreak-pattern signals across ICMR's wider national surveillance repository.", note_style),
        Paragraph("<b>Data governance.</b> All clinical records are de-identified and handled under "
                  "access-controlled, audit-logged safeguards consistent with ICMR data-governance protocols.",
                  note_style),
    ], [note_w, note_w], gap=gap2, valign='TOP', align='LEFT')
    items.append(notes)
    return items


def section_partnership(W):
    items = []
    items.append(Paragraph('INSTITUTIONAL PARTNERSHIP', styles['kicker']))
    items.append(Paragraph('A Collaboration Between AI Research and Public-Health Expertise', styles['h1']))
    items.append(Paragraph(
        "The project brings together specialist AI research capability with deep clinical and epidemiological "
        "expertise, under the umbrella of India's apex medical research body.", styles['lead']))
    items.append(Spacer(1, 10))

    gap = 14
    col_w = (W - 2 * gap) / 3
    partners = [
        ('amity_full_logo.png', 38,
         'Amity Centre for Artificial Intelligence, Amity University',
         'AI and machine-learning research, system design and model development.'),
        ('icmr_nie_logo.png', 32,
         'ICMR – National Institute of Epidemiology',
         "Clinical and epidemiological expertise, and access to India's national viral surveillance network."),
        ('dhr_logo.png', 58,
         'Department of Health Research, Government of India',
         'National public-health policy alignment and programme support.'),
    ]
    cards = []
    for fname, h, name, desc in partners:
        img = img_flowable(asset(fname), height=h)
        content = vstack([img, Paragraph(name, styles['partner_h']), Paragraph(desc, styles['partner_b'])],
                          col_w - 24, gaps=[8, 4], align='CENTER')
        cards.append(RoundedCard(content, col_w, bg=WHITE, border=CARD_BORDER, pad=14, radius=9))
    items.append(row(cards, [col_w] * 3, gap=gap))
    items.append(Spacer(1, 20))

    band_content = Paragraph('PROJECT SUPPORTED BY THE INDIAN COUNCIL OF MEDICAL RESEARCH (ICMR)',
                              ParagraphStyle('fund', fontName='Sans-Bold', fontSize=11,
                                             textColor=GOLD, alignment=TA_CENTER))
    items.append(RoundedCard(band_content, W, bg=NAVY_DEEP, pad=16, radius=9))
    items.append(Spacer(1, 22))

    items.append(Paragraph(
        "This partnership model — pairing Amity's AI research capability with ICMR's clinical and "
        "public-health authority — reflects a broader approach to translating advanced machine learning "
        "into tools that clinicians can trust and public-health laboratories can act on.", styles['lead']))
    items.append(Spacer(1, 4))
    items.append(Paragraph(
        f'Read more about ACAI’s research portfolio at '
        f'<a href="{SITE_URL}" color="#1565C0"><u>{SITE_URL.replace("https://", "")}</u></a>',
        ParagraphStyle('cta', fontName='Sans', fontSize=9.4, textColor=INK, leading=13)))
    return items


def section_team(W):
    items = []
    items.append(Paragraph('OUR TEAM', styles['kicker']))
    items.append(Paragraph('The People Behind the Project', styles['h1']))
    items.append(Paragraph(
        "A multidisciplinary team spanning artificial-intelligence research and clinical epidemiology leads "
        "the project's day-to-day work.", styles['lead']))
    items.append(Spacer(1, 12))

    def member(photo, name, affil_html):
        img = img_flowable(asset(photo), width=66)
        return vstack([img, Paragraph(name, styles['team_name']), Paragraph(affil_html, styles['team_role'])],
                       150, gaps=[7, 1], align='CENTER')

    def group_label(text):
        content = Paragraph(text.upper(), styles['group_lbl'])
        return RoundedCard(content, W, bg=NAVY, pad=7, radius=6)

    items.append(group_label('Principal Investigators'))
    items.append(Spacer(1, 12))
    items.append(center(row([
        member('team_dutta.png', 'Prof. M. K. Dutta', 'Amity Centre for<br/>Artificial Intelligence'),
        member('team_rizwan.png', 'Dr. Rizwan S A', 'ICMR, NIE'),
    ], [150, 150], gap=36), W))
    items.append(Spacer(1, 20))

    items.append(group_label('Co-Principal Investigators'))
    items.append(Spacer(1, 12))
    items.append(center(row([
        member('team_janani.png', 'R. Janani Surya', 'ICMR, NIE'),
        member('team_joshi.png', 'Dr. Rakesh C Joshi', 'Amity Centre for<br/>Artificial Intelligence'),
    ], [150, 150], gap=36), W))
    items.append(Spacer(1, 20))

    items.append(group_label('Project Scientist &amp; Contributor'))
    items.append(Spacer(1, 12))
    items.append(center(row([
        member('team_kaushal.png', 'Dr. Abhishek Kaushal', 'Amity Centre for<br/>Artificial Intelligence'),
        member('team_shikhar_placeholder.png', 'Shikhar Singh', 'Amity Centre for<br/>Artificial Intelligence'),
    ], [150, 150], gap=36), W))
    items.append(Spacer(1, 26))

    ack_content = Paragraph(
        "The team gratefully acknowledges the clinicians, laboratory staff and site investigators across "
        "ICMR's Virus Research & Diagnostic Laboratories network whose careful case reporting makes this "
        "system possible.",
        ParagraphStyle('ack', fontName='Sans-Italic', fontSize=9, textColor=MUTED,
                        leading=13, alignment=TA_CENTER))
    items.append(RoundedCard(ack_content, W, bg=PANEL, pad=14, radius=9))

    return items


# ---------------------------------------------------------------------------
# Document assembly
# ---------------------------------------------------------------------------
def build():
    doc = BaseDocTemplate(
        OUT_PDF, pagesize=A4,
        leftMargin=46, rightMargin=46, topMargin=100, bottomMargin=64,
        title="Personalized Recommender System for Virus Research and Diagnosis Laboratory Network",
        author="Amity Centre for Artificial Intelligence, Amity University",
        subject="AI-based clinical decision-support system for viral-infection triage and laboratory test "
                "recommendation, developed with ICMR - National Institute of Epidemiology.",
        creator="Amity Centre for Artificial Intelligence",
    )

    cover_frame = Frame(0, 0, PAGE_W, PAGE_H, id='cover', showBoundary=0,
                        leftPadding=0, rightPadding=0, topPadding=0, bottomPadding=0)
    inner_frame = Frame(46, 64, PAGE_W - 92, PAGE_H - 100 - 64, id='inner', showBoundary=0)

    doc.addPageTemplates([
        PageTemplate(id='Cover', frames=[cover_frame], onPage=draw_cover),
        PageTemplate(id='Inner', frames=[inner_frame], onPage=draw_inner),
    ])

    W = PAGE_W - 92

    story = [Spacer(1, 1), NextPageTemplate('Inner'), PageBreak()]
    story += section_overview(W)
    story.append(PageBreak())
    story += section_methodology(W)
    story.append(PageBreak())
    story += section_scope(W)
    story.append(PageBreak())
    story += section_partnership(W)
    story.append(PageBreak())
    story += section_team(W)

    doc.build(story)
    print('PDF written to', OUT_PDF)


if __name__ == '__main__':
    build()
