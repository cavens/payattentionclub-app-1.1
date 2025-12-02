## send-week-end-reminders

Edge Function that emails everyone whose commitment week ends **today (Monday)** reminding them to open the app before the Tuesday noon ET grace deadline.

### Environment variables

Set these secrets in Supabase:

| Key | Purpose |
| --- | --- |
| `LOOPS_API_KEY` | Loops transactional API key |
| `LOOPS_REMINDER_TEMPLATE_ID` | Transactional notification ID (`transactionalId`) |
| `LOOPS_API_BASE_URL` (optional) | Override for non-default Loops endpoint |
| `SUPABASE_URL` | Provided automatically in Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Provided automatically in Supabase |

### Local testing

```bash
cd supabase
supabase functions serve send-week-end-reminders \
  --env-file ./functions/.env.development \
  --no-verify-jwt
```

Then `curl -X POST http://localhost:54321/functions/v1/send-week-end-reminders \
  -H "Content-Type: application/json" \
  -d '{"deadline":"2025-12-01"}'`

> The optional `deadline` override lets you test specific Mondays.

### Production schedule

Add a Supabase cron job:

- **Endpoint:** `https://<project-ref>.functions.supabase.co/send-week-end-reminders`
- **Method:** `POST`
- **Schedule:** `CRON_TZ=America/New_York 5 12 * * 1` (every Monday 12:05 ET)

The function calls `https://app.loops.so/api/v1/transactional` and includes the `transactionalId` from `LOOPS_REMINDER_TEMPLATE_ID`, so make sure that ID matches the one shown in the Loops UI. The function responds with a JSON summary so failures are easy to alert on.

