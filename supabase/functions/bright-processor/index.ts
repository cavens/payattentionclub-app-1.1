import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");
const LOOPS_API_KEY = Deno.env.get("LOOPS_API_KEY");
const LOOPS_TEMPLATE_ID = Deno.env.get("LOOPS_REMINDER_TEMPLATE_ID");
const LOOPS_API_URL = Deno.env.get("LOOPS_API_BASE_URL") ?? "https://app.loops.so/api/v1/transactional";
const TIME_ZONE = "America/New_York"; // Align with product deadline (Monday noon ET)

if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error("Missing Supabase service credentials. Please set SUPABASE_URL and SUPABASE_SECRET_KEY.");
}
if (!LOOPS_API_KEY || !LOOPS_TEMPLATE_ID) {
  console.error("Missing Loops credentials. Please set LOOPS_API_KEY and LOOPS_REMINDER_TEMPLATE_ID.");
}

type CommitmentRow = {
  id: string;
  user_id: string;
  week_end_timestamp: string;  // Primary source of truth (both modes)
  week_grace_expires_at: string | null;
};

type UserRow = {
  id: string;
  email: string | null;
};

function getDateInTimeZone(date: Date, timeZone: string): Date {
  // Converts the incoming date into the desired time zone by leveraging locale formatting.
  const locale = date.toLocaleString("en-US", { timeZone });
  return new Date(locale);
}

function formatDate(date: Date): string {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function getMondayDeadline(now: Date): { mondayDate: Date; mondayString: string } {
  const nowEt = getDateInTimeZone(now, TIME_ZONE);
  const dayOfWeek = nowEt.getDay(); // 0 = Sunday, 1 = Monday
  const monday = new Date(nowEt);

  if (dayOfWeek === 0) {
    // Sunday → use tomorrow (Monday)
    monday.setDate(monday.getDate() + 1);
  } else if (dayOfWeek > 1) {
    // Tue-Sat → go back to last Monday
    monday.setDate(monday.getDate() - (dayOfWeek - 1));
  }
  // Monday stays as-is.
  const mondayNoTime = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate());
  return {
    mondayDate: mondayNoTime,
    mondayString: formatDate(mondayNoTime)
  };
}

function toIsoDate(dateString: string | null | undefined): string | null {
  if (!dateString) return null;
  const d = new Date(dateString);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

async function sendLoopsReminder(email: string, payload: Record<string, unknown>) {
  const url = LOOPS_API_URL;
  const body = {
    transactionalId: LOOPS_TEMPLATE_ID,
    email,
    data: payload
  };
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${LOOPS_API_KEY}`
    },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    const errBody = await res.text();
    throw new Error(`Loops API error (${res.status}): ${errBody}`);
  }
  return res.json();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Use POST", { status: 405 });
  }

  const supabase = createClient(SUPABASE_URL!, SUPABASE_SECRET_KEY!);
  let overrideDeadline: string | undefined;
  try {
    const body = await req.json();
    if (body?.deadline) {
      overrideDeadline = body.deadline;
    }
  } catch (_err) {
    // Ignore body parse errors (allow empty POSTs)
  }

  const now = new Date();
  const { mondayDate, mondayString } = overrideDeadline
    ? { mondayDate: new Date(overrideDeadline), mondayString: overrideDeadline }
    : getMondayDeadline(now);

  console.log("Reminder target Monday:", mondayString);

  // Use timestamp range lookup to find commitments ending on the Monday date
  const mondayDateStart = new Date(`${mondayString}T00:00:00`);
  const mondayDateEnd = new Date(`${mondayString}T23:59:59.999`);
  const { data: commitments, error: commitmentsError } = await supabase
    .from("commitments")
    .select("id, user_id, week_end_timestamp, week_grace_expires_at")
    .gte("week_end_timestamp", mondayDateStart.toISOString())
    .lte("week_end_timestamp", mondayDateEnd.toISOString());

  if (commitmentsError) {
    console.error("Error fetching commitments:", commitmentsError);
    return new Response("Error fetching commitments", { status: 500 });
  }

  const uniqueUserIds = Array.from(new Set((commitments ?? []).map((c) => c.user_id)));
  if (uniqueUserIds.length === 0) {
    console.log("No commitments ending on", mondayString);
    return new Response(JSON.stringify({ processed: 0, remindersSent: 0 }), {
      headers: { "Content-Type": "application/json" }
    });
  }

  const { data: users, error: usersError } = await supabase
    .from("users")
    .select("id, email")
    .in("id", uniqueUserIds);

  if (usersError) {
    console.error("Error fetching users:", usersError);
    return new Response("Error fetching users", { status: 500 });
  }

  const userMap = new Map<string, UserRow>();
  for (const user of users ?? []) {
    userMap.set(user.id, user);
  }

  const summary = {
    processedCommitments: commitments?.length ?? 0,
    targetedUsers: uniqueUserIds.length,
    remindersSent: 0,
    skipped: {
      missingEmail: 0,
      duplicateEmail: 0
    },
    errors: [] as string[]
  };

  const emailed = new Set<string>();

  for (const commitment of commitments ?? []) {
    const user = userMap.get(commitment.user_id);
    if (!user?.email) {
      summary.skipped.missingEmail += 1;
      continue;
    }
    if (emailed.has(user.email)) {
      summary.skipped.duplicateEmail += 1;
      continue;
    }

    const graceIso =
      toIsoDate(commitment.week_grace_expires_at) ??
      toIsoDate(new Date(mondayDate.getTime() + 24 * 60 * 60 * 1000).toISOString());

    try {
      await sendLoopsReminder(user.email, {
        week_end_date: new Date(commitment.week_end_timestamp).toISOString().split('T')[0],  // Extract date from timestamp for metadata
        grace_deadline: graceIso,
        email: user.email
      });
      emailed.add(user.email);
      summary.remindersSent += 1;
    } catch (err) {
      console.error("Failed to send reminder for user", user.id, err);
      summary.errors.push(`user:${user.id} -> ${(err as Error).message}`);
    }
  }

  return new Response(JSON.stringify(summary), {
    headers: { "Content-Type": "application/json" }
  });
});