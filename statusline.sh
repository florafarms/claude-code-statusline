#!/bin/bash
INPUT=$(cat)
export STATUSLINE_INPUT="$INPUT"

python3 << 'PYEOF'
import json, os, subprocess, time, glob
from datetime import datetime, timezone, timedelta

data = json.loads(os.environ.get('STATUSLINE_INPUT', '{}'))

# ANSI
R    = '\033[91m'
O    = '\033[38;5;208m'
G    = '\033[92m'
B    = '\033[94m'
Y    = '\033[93m'
M    = '\033[95m'         # Opus
C    = '\033[96m'         # Sonnet
F    = '\033[38;5;213m'   # Fable
H    = '\033[92m'         # Haiku
GR   = '\033[90m'
D    = '\033[2m'
X    = '\033[0m'
SEP  = f' {D}|{X} '

cost_data    = data.get('cost', {})
session_cost = cost_data.get('total_cost_usd', 0)

# Modelo activo de la sesión
model_info    = data.get('model', {})
active_lower  = (model_info.get('display_name') or '').lower()
if   'mythos' in active_lower: active_fam = 'fable'
elif 'fable'  in active_lower: active_fam = 'fable'
elif 'opus'   in active_lower: active_fam = 'opus'
elif 'sonnet' in active_lower: active_fam = 'sonnet'
elif 'haiku'  in active_lower: active_fam = 'haiku'
else:                          active_fam = None

cache_file = os.path.expanduser('~/.claude/scripts/.statusline_cache.json')
cache_ttl  = 30

cache = None
try:
    if os.path.exists(cache_file) and time.time() - os.path.getmtime(cache_file) < cache_ttl:
        with open(cache_file) as f:
            cache = json.load(f)
except:
    pass

if cache is None:
    cache = {'quota': None, 'block': None, 'daily': None}
    # 1) Cuota oficial Anthropic
    try:
        tok_raw = subprocess.run(
            ['security', 'find-generic-password', '-s', 'Claude Code-credentials', '-w'],
            capture_output=True, text=True, timeout=3
        ).stdout.strip()
        token = json.loads(tok_raw)['claudeAiOauth']['accessToken']
        r = subprocess.run([
            'curl', '-sS', '--max-time', '4',
            '-H', f'Authorization: Bearer {token}',
            '-H', 'anthropic-beta: oauth-2025-04-20',
            'https://api.anthropic.com/api/oauth/usage'
        ], capture_output=True, text=True, timeout=5)
        if r.returncode == 0 and r.stdout.strip():
            q = json.loads(r.stdout)
            if 'error' not in q:
                cache['quota'] = q
    except:
        pass
    # 2) Bloque activo (ccusage) — para burn rate
    try:
        r = subprocess.run(['ccusage', 'blocks', '--active', '--json'],
                           capture_output=True, text=True, timeout=4)
        if r.returncode == 0:
            bl = json.loads(r.stdout).get('blocks', [])
            cache['block'] = bl[0] if bl else None
    except:
        pass
    # 3) Daily breakdown
    try:
        r = subprocess.run(['ccusage', 'daily', '--breakdown', '--json'],
                           capture_output=True, text=True, timeout=4)
        if r.returncode == 0:
            d = json.loads(r.stdout).get('daily', [])
            cache['daily'] = d[-1] if d else None
    except:
        pass
    try:
        with open(cache_file, 'w') as f:
            json.dump(cache, f)
    except:
        pass

# --- Cuota Anthropic (la fuente de verdad) + fallback persistente ---
last_quota_file = os.path.expanduser('~/.claude/scripts/.quota_last_seen.json')
quota = cache.get('quota')
quota_stale = False
quota_age_min = 0

if quota:
    try:
        with open(last_quota_file, 'w') as f:
            json.dump({'quota': quota, 'saved_at': time.time()}, f)
    except: pass
else:
    quota = {}
    if os.path.exists(last_quota_file):
        try:
            with open(last_quota_file) as f:
                snap = json.load(f)
            quota = snap.get('quota') or {}
            quota_age_min = int((time.time() - snap.get('saved_at', 0)) / 60)
            quota_stale = True
        except: pass

fh = quota.get('five_hour') or {}
sd = quota.get('seven_day') or {}
op = quota.get('seven_day_opus') or {}

fh_pct = fh.get('utilization')
sd_pct = sd.get('utilization')
op_pct = op.get('utilization') if op else None

def pct_color(p):
    if p is None: return GR
    if p < 50:    return G
    if p < 80:    return Y
    return R

def fmt_reset(iso):
    if not iso: return ''
    try:
        dt = datetime.fromisoformat(iso.replace('Z', '+00:00'))
        delta = dt - datetime.now(timezone.utc)
        s = int(delta.total_seconds())
        if s <= 0: return '0m'
        d = s // 86400
        h = (s % 86400) // 3600
        m = (s % 3600) // 60
        if d > 0:
            return f'{d}d{h:02d}h' if h else f'{d}d'
        return f'{h}h{m:02d}m' if h else f'{m}m'
    except:
        return ''

fh_reset = fmt_reset(fh.get('resets_at'))
sd_reset = fmt_reset(sd.get('resets_at'))

# --- Burn rate del bloque ccusage ---
block = cache.get('block') or {}
burn_per_h = (block.get('burnRate') or {}).get('costPerHour', 0)
block_tokens = block.get('totalTokens', 0)
remain_min_block = (block.get('projection') or {}).get('remainingMinutes', 0)

# --- Desglose por modelo del bloque (parseando JSONLs) ---
# 'mythos' comparte modelo con Fable; se agrupa como Fable
MODEL_FAMILIES = [('fable', ['fable', 'mythos']),
                  ('opus', ['opus']),
                  ('sonnet', ['sonnet']),
                  ('haiku', ['haiku'])]
model_block = {fam: 0 for fam, _ in MODEL_FAMILIES}
start_iso = block.get('startTime')
if start_iso:
    try:
        start_dt = datetime.fromisoformat(start_iso.replace('Z', '+00:00'))
        for jl in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
            try:
                if os.path.getmtime(jl) < start_dt.timestamp() - 60:
                    continue
                with open(jl, 'r', errors='ignore') as f:
                    for line in f:
                        try:
                            e = json.loads(line)
                            ts = e.get('timestamp')
                            if not ts: continue
                            dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
                            if dt < start_dt: continue
                            msg = e.get('message') or {}
                            u   = msg.get('usage') or {}
                            model = (msg.get('model') or '').lower()
                            tk = (u.get('input_tokens', 0) + u.get('output_tokens', 0)
                                  + u.get('cache_creation_input_tokens', 0)
                                  + u.get('cache_read_input_tokens', 0))
                            for fam, keys in MODEL_FAMILIES:
                                if any(k in model for k in keys):
                                    model_block[fam] += tk
                                    break
                        except: continue
            except: continue
    except: pass

def fmt_tk(n):
    if n >= 1_000_000: return f'{n/1_000_000:.1f}M'
    if n >= 1_000:     return f'{n/1_000:.0f}K'
    return str(n)

# --- Fallback: si no hay % oficial, estimar con datos locales ---
BLOCK_TOKEN_CEILING = 220_000_000  # techo histórico aprox para 1 bloque 5h plan Max
fh_estimated = False
sd_estimated = False

if fh_pct is None:
    fh_pct = min(100.0, (block_tokens / BLOCK_TOKEN_CEILING) * 100) if block_tokens else 0
    fh_estimated = True
    if not fh_reset and remain_min_block:
        h = remain_min_block // 60
        m = remain_min_block % 60
        fh_reset = f'{h}h{m:02d}m'

if sd_pct is None:
    # Estimación 7d: sumar tokens últimos 7 días de daily JSONLs vs techo semanal
    SEM_TOKEN_CEILING = 1_500_000_000
    try:
        r = subprocess.run(['ccusage', 'daily', '--json'],
                           capture_output=True, text=True, timeout=4)
        if r.returncode == 0:
            dd = json.loads(r.stdout).get('daily', [])
            recent = sum(d.get('totalTokens', 0) for d in dd[-7:])
            sd_pct = min(100.0, (recent / SEM_TOKEN_CEILING) * 100)
            sd_estimated = True
    except: pass
    if sd_pct is None: sd_pct = 0

# Fallback del reset semanal: lunes 12:00 UTC más próximo
if not sd_reset:
    try:
        now_utc = datetime.now(timezone.utc)
        days_ahead = (0 - now_utc.weekday()) % 7  # 0 = lunes
        next_mon = (now_utc + timedelta(days=days_ahead)).replace(hour=12, minute=0, second=0, microsecond=0)
        if next_mon <= now_utc:
            next_mon += timedelta(days=7)
        sd_reset = fmt_reset(next_mon.isoformat())
    except: sd_reset = ''

def fmt_pct(p, est=False):
    prefix = '~' if est else ''
    return f'{prefix}{p:.0f}%'

# --- Salida ---
parts = []
parts.append(f'💰 {GR}${session_cost:.2f}{X}')
parts.append(f'🔥 {R}${burn_per_h:.2f}/h{X}')
parts.append(f'📊 5h {pct_color(fh_pct)}{fmt_pct(fh_pct, fh_estimated)}{X} {D}({fh_reset or "?"}){X}')
parts.append(f'🗓 7d {pct_color(sd_pct)}{fmt_pct(sd_pct, sd_estimated)}{X} {D}({sd_reset or "?"}){X}')
if op_pct is not None:
    parts.append(f'🧠 Opus {pct_color(op_pct)}{fmt_pct(op_pct)}{X}')
MODEL_STYLES = {'fable': ('F', F), 'opus': ('O', M), 'sonnet': ('S', C), 'haiku': ('H', H)}
segs = []
for fam, _ in MODEL_FAMILIES:
    # Mostrar familia si tiene uso en el bloque, o si es el modelo activo ahora
    if model_block[fam] > 0 or fam == active_fam:
        letter, color = MODEL_STYLES[fam]
        robot = '🤖' if fam == active_fam else ''
        segs.append(f'{robot}{color}{letter} {fmt_tk(model_block[fam])}{X}')
if segs:
    parts.append('·'.join(segs))
if quota_stale:
    parts.append(f'{D}⚠ datos {quota_age_min}m{X}')

print('  '.join(parts))
PYEOF
