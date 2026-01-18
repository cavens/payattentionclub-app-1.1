// supabase/functions/admin-close-week-now/index.ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SECRET_KEY = Deno.env.get("SUPABASE_SECRET_KEY");
Deno.serve(async (req)=>{
  try {
    // Only allow POST
    if (req.method !== "POST") {
      return new Response(JSON.stringify({
        error: "Use POST"
      }), {
        status: 405
      });
    }
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({
        error: "Missing Authorization header"
      }), {
        status: 401
      });
    }
    // Supabase client with service role, but aware of caller's JWT
    const supabase = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY, {
      global: {
        headers: {
          Authorization: authHeader
        }
      }
    });
    // 1) Get current user from JWT
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    if (userError || !user) {
      return new Response(JSON.stringify({
        error: "Not authenticated"
      }), {
        status: 401
      });
    }
    const userId = user.id;
    // 2) Load public.users row and check is_test_user
    const { data: dbUser, error: dbUserError } = await supabase.from("users").select("id, email, is_test_user").eq("id", userId).maybeSingle();
    if (dbUserError || !dbUser) {
      console.error("Error fetching public.users row:", dbUserError);
      return new Response(JSON.stringify({
        error: "User not found in public.users"
      }), {
        status: 400
      });
    }
    if (!dbUser.is_test_user) {
      console.warn("admin-close-week-now denied for non-test user:", dbUser.email);
      return new Response(JSON.stringify({
        error: "Forbidden"
      }), {
        status: 403
      });
    }
    // 3) Call the weekly-close Edge Function directly
    // This gives us the actual output from weekly-close
    const weeklyCloseUrl = `${SUPABASE_URL}/functions/v1/weekly-close`;
    const weeklyCloseResponse = await fetch(weeklyCloseUrl, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${SUPABASE_SECRET_KEY}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({})
    });
    
    if (!weeklyCloseResponse.ok) {
      const errorText = await weeklyCloseResponse.text();
      console.error("Error calling weekly-close:", errorText);
      return new Response(JSON.stringify({
        error: "Failed to trigger weekly close",
        details: errorText
      }), {
        status: weeklyCloseResponse.status
      });
    }
    
    const weeklyCloseResult = await weeklyCloseResponse.json();
    
    return new Response(JSON.stringify({
      ok: true,
      message: "Weekly close triggered",
      triggeredBy: dbUser.email,
      result: weeklyCloseResult
    }), {
      status: 200,
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (err) {
    console.error("admin-close-week-now error:", err);
    return new Response(JSON.stringify({
      error: "Internal server error"
    }), {
      status: 500
    });
  }
});
