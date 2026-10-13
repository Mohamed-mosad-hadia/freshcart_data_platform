# Postmortem: <incident title>

> Blameless: describe what the SYSTEM allowed to happen, not who made a mistake.

| | |
|---|---|
| Date of incident | |
| Authors | |
| Severity | SEV-1 / SEV-2 / SEV-3 |

## 1. Summary
Three to five sentences a non-engineer understands: what broke, for how long, who was
affected, and whether any number was WRONG (not just late).

## 2. Impact
- Which tables / dashboards were late, and by how much?
- Was anything wrong or lost? How do you know?

## 3. Timeline (Cairo time)
| Time | Event |
|---|---|
| | First failure (cite the Airflow log) |
| | Detected (which alert?) |
| | Recovery started |
| | Data verified complete and correct |

## 4. Detection
How was it detected, and how long after it started? What would have detected it sooner?

## 5. Root cause and contributing factors
The root cause may be outside our control. Focus on what inside our platform made the
impact bigger or the recovery harder. Ask "why?" five times.

## 6. Recovery
The exact steps taken, and how you proved every day is complete and correct afterwards.

## 7. What went well / what went badly / where we got lucky

## 8. Action items
| # | Action | Prevent / detect / mitigate | Owner | Priority |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
