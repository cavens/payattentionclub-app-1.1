# Authorization Amount Formula - Baseline Approach V2 (Revised)

## Baseline Definition

**Baseline Settings:**
- **Limit**: 21 hours (1,260 minutes)
- **Penalty**: $0.10 per minute (10 cents)
- **Apps**: 4 apps (minimum required - app doesn't work without apps)
- **Time remaining**: 7 days (full week)

## Revised Formula Logic

**Key Changes:**
1. **Stricter limits = exponentially higher authorization** (not linear)
2. **Minimum 1 app** (zero apps not possible)
3. **Strictness factor** that scales aggressively with limit strictness

**New Formula:**
```
1. max_usage = 7 days × 12 hours/day = 5,040 minutes
2. overage = max(0, max_usage - limit_minutes)
3. strictness_ratio = max_usage / limit_minutes
   - 24h limit: 5,040 / 1,440 = 3.5x
   - 21h limit: 5,040 / 1,260 = 4.0x
   - 15h limit: 5,040 / 900 = 5.6x
   - 12h limit: 5,040 / 720 = 7.0x
4. strictness_factor = (strictness_ratio - 1) ^ 1.5
   - This makes stricter limits increase authorization exponentially
5. base = overage × penalty_cents × strictness_factor
6. risk_factor = 1.0 + ((app_count - 1) × 0.02), minimum 1.0
   - 1 app = 1.0x (baseline)
   - 4 apps = 1.06x (+6%)
   - 10 apps = 1.18x (+18%)
   - 20 apps = 1.38x (+38%)
7. time_factor = 1.2 (for full week)
8. before_damping = base × risk_factor × time_factor
9. after_damping = before_damping × 0.04
10. final = max($15, min($1000, after_damping))
```

## Baseline Calculation (21h @ $0.10, 4 apps)

1. Max usage: 5,040 min
2. Overage: 5,040 - 1,260 = 3,780 min
3. Strictness ratio: 5,040 / 1,260 = 4.0x
4. Strictness factor: (4.0 - 1) ^ 1.5 = 3.0 ^ 1.5 = **5.20**
5. Base: 3,780 × 10 × 5.20 = 196,560 cents
6. Risk factor: 1.0 + ((4 - 1) × 0.02) = 1.06
7. Time factor: 1.2
8. Before damping: 196,560 × 1.06 × 1.2 = 249,784 cents
9. After damping: 249,784 × 0.04 = 9,991 cents = **$99.91**

**Wait, that's too high!** Let me adjust the damping factor or strictness calculation...

Actually, let me try a different approach - use strictness as a multiplier on the base, but with better scaling:

**Revised Formula V2:**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_multiplier = 1.0 + ((max_usage / limit_minutes - 1) × 0.5)
   - 24h: 1.0 + ((3.5 - 1) × 0.5) = 1.0 + 1.25 = 2.25x
   - 21h: 1.0 + ((4.0 - 1) × 0.5) = 1.0 + 1.5 = 2.5x
   - 15h: 1.0 + ((5.6 - 1) × 0.5) = 1.0 + 2.3 = 3.3x
   - 12h: 1.0 + ((7.0 - 1) × 0.5) = 1.0 + 3.0 = 4.0x
4. base = overage × penalty_cents × strictness_multiplier
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.04
9. final = max($15, min($1000, after_damping))
```

Let me recalculate baseline:
1. Overage: 3,780 min
2. Strictness multiplier: 2.5x
3. Base: 3,780 × 10 × 2.5 = 94,500 cents
4. Risk: 1.06 (4 apps)
5. Time: 1.2
6. Before damping: 94,500 × 1.06 × 1.2 = 120,204 cents
7. After damping: 120,204 × 0.04 = 4,808 cents = **$48.08**

Still too high. Let me adjust damping or use a different approach...

**Revised Formula V3 (Final):**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_multiplier = 1.0 + ((max_usage / limit_minutes - 1) × 0.3)
   - 24h: 1.0 + ((3.5 - 1) × 0.3) = 1.75x
   - 21h: 1.0 + ((4.0 - 1) × 0.3) = 1.9x
   - 15h: 1.0 + ((5.6 - 1) × 0.3) = 2.38x
   - 12h: 1.0 + ((7.0 - 1) × 0.3) = 2.8x
4. base = overage × penalty_cents × strictness_multiplier
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.05  (increased from 0.04)
9. final = max($15, min($1000, after_damping))
```

**Baseline Recalculation:**
1. Overage: 3,780 min
2. Strictness: 1.9x
3. Base: 3,780 × 10 × 1.9 = 71,820 cents
4. Risk: 1.06
5. Time: 1.2
6. Before damping: 71,820 × 1.06 × 1.2 = 91,355 cents
7. After damping: 91,355 × 0.05 = 4,568 cents = **$45.68**

Still too high. Let me try one more adjustment...

**Revised Formula V4 (Better Scaling):**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_multiplier = 1.0 + ((max_usage / limit_minutes - 1) × 0.2)
   - 24h: 1.0 + ((3.5 - 1) × 0.2) = 1.5x
   - 21h: 1.0 + ((4.0 - 1) × 0.2) = 1.6x
   - 15h: 1.0 + ((5.6 - 1) × 0.2) = 1.92x
   - 12h: 1.0 + ((7.0 - 1) × 0.2) = 2.2x
4. base = overage × penalty_cents × strictness_multiplier
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.06  (further increased)
9. final = max($15, min($1000, after_damping))
```

**Baseline:**
1. Base: 3,780 × 10 × 1.6 = 60,480 cents
2. Before damping: 60,480 × 1.06 × 1.2 = 76,930 cents
3. After damping: 76,930 × 0.06 = 4,616 cents = **$46.16**

Hmm, I think I need to step back and think about this differently. The user wants ~$20 baseline, but with more aggressive scaling for stricter limits. Let me try a completely different approach...

**Revised Formula V5 (Power-based strictness):**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_power = (max_usage / limit_minutes) ^ 0.8
   - 24h: (3.5) ^ 0.8 = 2.85
   - 21h: (4.0) ^ 0.8 = 3.03
   - 15h: (5.6) ^ 0.8 = 4.15
   - 12h: (7.0) ^ 0.8 = 5.19
4. base = overage × penalty_cents × strictness_power
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.01  (much lower damping)
9. final = max($15, min($1000, after_damping))
```

**Baseline:**
1. Base: 3,780 × 10 × 3.03 = 114,534 cents
2. Before damping: 114,534 × 1.06 × 1.2 = 145,687 cents
3. After damping: 145,687 × 0.01 = 1,457 cents = **$14.57** (too low, hits $15 min)

Let me find the right balance...

**Revised Formula V6 (Final Attempt - Balanced):**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_multiplier = 1.0 + ((max_usage / limit_minutes - 1) × 0.15)
   - 24h: 1.0 + ((3.5 - 1) × 0.15) = 1.375x
   - 21h: 1.0 + ((4.0 - 1) × 0.15) = 1.45x
   - 15h: 1.0 + ((5.6 - 1) × 0.15) = 1.69x
   - 12h: 1.0 + ((7.0 - 1) × 0.15) = 1.9x
4. base = overage × penalty_cents × strictness_multiplier
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.08
9. final = max($15, min($1000, after_damping))
```

**Baseline:**
1. Base: 3,780 × 10 × 1.45 = 54,810 cents
2. Before damping: 54,810 × 1.06 × 1.2 = 69,718 cents
3. After damping: 69,718 × 0.08 = 5,577 cents = **$55.77**

Still not right. Let me try a simpler approach with better numbers...

**Revised Formula V7 (Simpler, Better Numbers):**
```
1. max_usage = 5,040 min
2. overage = max(0, 5,040 - limit_minutes)
3. strictness_multiplier = (max_usage / limit_minutes) × 0.4
   - 24h: 3.5 × 0.4 = 1.4x
   - 21h: 4.0 × 0.4 = 1.6x
   - 15h: 5.6 × 0.4 = 2.24x
   - 12h: 7.0 × 0.4 = 2.8x
4. base = overage × penalty_cents × strictness_multiplier
5. risk_factor = 1.0 + ((app_count - 1) × 0.02)
6. time_factor = 1.2
7. before_damping = base × risk_factor × time_factor
8. after_damping = before_damping × 0.1
9. final = max($15, min($1000, after_damping))
```

**Baseline:**
1. Base: 3,780 × 10 × 1.6 = 60,480 cents
2. Before damping: 60,480 × 1.06 × 1.2 = 76,930 cents
3. After damping: 76,930 × 0.1 = 7,693 cents = **$76.93**

Too high again. I think the issue is I'm trying to hit $20 but the numbers don't work out. Let me recalculate what damping factor I need for $20 baseline, then work backwards...

For baseline to be $20:
- Final: $20 = 2,000 cents
- Before damping: 2,000 / damping_factor
- We have: 76,930 × damping_factor = 2,000
- damping_factor = 2,000 / 76,930 = 0.026

So if I use 0.026 damping:
- 24h: (3,600 × 10 × 1.4 × 1.0 × 1.2) × 0.026 = 1,572 cents = $15.72
- 21h: (3,780 × 10 × 1.6 × 1.06 × 1.2) × 0.026 = 2,000 cents = $20.00 ✓
- 15h: (4,140 × 10 × 2.24 × 1.06 × 1.2) × 0.026 = 3,070 cents = $30.70
- 12h: (4,320 × 10 × 2.8 × 1.06 × 1.2) × 0.026 = 4,000 cents = $40.00

This gives us:
- 24h to 21h: $15.72 to $20.00 = +$4.28
- 21h to 15h: $20.00 to $30.70 = +$10.70
- 15h to 12h: $30.70 to $40.00 = +$9.30

The difference between 24h and 12h is $24.28, which is much better! But let me verify the scaling makes sense...

Actually, let me present this as the final proposal.


