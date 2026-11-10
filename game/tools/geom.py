"""Road geometry shared by the graphics and table generators.

The road is a 72-row perspective strip. Row 0 is the horizon, row 71 the bottom.
Distances are measured in stripe periods (one light + one dark band)."""
ROWS = 72
HORIZON = 56            # screen line of row 0 on flat ground
ROAD_BOTTOM = 127       # screen line of row 71 on flat ground (HUD starts at 128)
SKY_ROWS = 80           # height of the sky picture in the BG map (pixels)
ZK = 126.0              # z(row) = ZK / (row + 1) periods
PITCH_MAX = 8           # hill curvature range -8..8
HILL_K = 2520.0         # horizon moves 2 px per pitch unit


def half_width(r):
    """Road half-width in pixels at row r."""
    return 3 + 74.0 * r / 71.0


def z_of(r):
    return ZK / (r + 1)


def row_of(d):
    """Row whose distance is d periods (72+ when nearer than the bottom row, -1 beyond the horizon)."""
    if d <= 0: return 127
    r = int(ZK / d) - 1
    if r < 0: return -1
    return min(r, 127)


def hill_map(p):
    """For pitch p: (line_rows, inv). line_rows[i] is the texture row shown on screen line
    127-i; inv[r] is the screen line where row r sits."""
    rows, inv = [], [0] * ROWS
    ycur = ROAD_BOTTOM + 1
    for r in range(ROWS - 1, -1, -1):
        k = ROWS - 1 - r
        y = int(round(HORIZON + r - p * k * k / HILL_K))
        if y < ycur:
            for _ in range(ycur - y): rows.append(r)
            ycur = y
        inv[r] = min(y, ROAD_BOTTOM) if y < ycur + 1 else ycur
    return rows, inv
