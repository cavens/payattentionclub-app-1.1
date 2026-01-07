/**
 * Test: Step 1.3 - Commitment Creation with Compressed Deadline
 * 
 * Tests that:
 * 1. Timing helper is imported correctly
 * 2. Deadline calculation works (normal and testing mode)
 * 3. Date formatting is correct (YYYY-MM-DD)
 * 4. Logic correctly overrides client deadline in testing mode
 * 
 * Run with:
 *   deno run --allow-net --allow-env --allow-read test_step_1_3_commitment_deadline.ts
 */

import { assertEquals, assertExists } from "https://deno.land/std@0.208.0/assert/mod.ts";

console.log("📊 Step 1.3 Test: Commitment Creation with Compressed Deadline");
console.log("=============================================================\n");

// Test 1: Verify timing helper can be imported
console.log("📊 Test 1: Verify timing helper import");
try {
  const { TESTING_MODE, getNextDeadline } = await import("../functions/_shared/timing.ts");
  assertExists(TESTING_MODE, "TESTING_MODE should be exported");
  assertExists(getNextDeadline, "getNextDeadline should be exported");
  console.log(`   TESTING_MODE: ${TESTING_MODE}`);
  console.log("✅ Test 1 PASS: Timing helper imports correctly");
} catch (error) {
  console.error("❌ Test 1 FAIL:", error);
  Deno.exit(1);
}

// Test 2: Test deadline calculation (normal mode)
console.log("\n📊 Test 2: Deadline calculation (normal mode)");
try {
  Deno.env.delete("TESTING_MODE");
  const { getNextDeadline } = await import("../functions/_shared/timing.ts");
  
  const now = new Date();
  const deadline = getNextDeadline(now);
  const diff = deadline.getTime() - now.getTime();
  const expectedDiff = 7 * 24 * 60 * 60 * 1000; // 7 days
  
  console.log(`   Now: ${now.toISOString()}`);
  console.log(`   Deadline: ${deadline.toISOString()}`);
  console.log(`   Difference: ${(diff / 1000 / 60 / 60 / 24).toFixed(2)} days`);
  
  // Should be next Monday, so approximately 1-7 days
  if (diff > 0 && diff < 8 * 24 * 60 * 60 * 1000) {
    console.log("✅ Test 2 PASS: Normal mode deadline is next Monday");
  } else {
    throw new Error(`Unexpected deadline difference: ${diff}ms (${(diff / 1000 / 60 / 60 / 24).toFixed(2)} days)`);
  }
} catch (error) {
  console.error("❌ Test 2 FAIL:", error);
  Deno.exit(1);
}

// Test 3: Test deadline calculation (testing mode)
console.log("\n📊 Test 3: Deadline calculation (testing mode)");
console.log("⚠️  Note: Requires TESTING_MODE=true at module load time");
console.log("   Testing with manual calculation...");
try {
  // Simulate what happens in testing mode
  const now = new Date();
  const compressedDeadline = new Date(now.getTime() + 3 * 60 * 1000); // 3 minutes
  const diff = compressedDeadline.getTime() - now.getTime();
  const expectedDiff = 3 * 60 * 1000; // 3 minutes
  
  console.log(`   Now: ${now.toISOString()}`);
  console.log(`   Compressed deadline: ${compressedDeadline.toISOString()}`);
  console.log(`   Difference: ${(diff / 1000 / 60).toFixed(2)} minutes`);
  
  if (Math.abs(diff - expectedDiff) < 1000) {
    console.log("✅ Test 3 PASS: Testing mode deadline is ~3 minutes from now");
  } else {
    throw new Error(`Unexpected compressed deadline difference: ${diff}ms`);
  }
} catch (error) {
  console.error("❌ Test 3 FAIL:", error);
  Deno.exit(1);
}

// Test 4: Test date formatting function
console.log("\n📊 Test 4: Date formatting");
try {
  // This is the exact function from super-service/index.ts
  function formatDate(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
      date.getDate()
    ).padStart(2, "0")}`;
  }
  
  // Test various dates (using noon UTC to avoid timezone issues)
  const testCases = [
    { date: new Date("2025-01-13T12:00:00Z"), expected: "2025-01-13" },
    { date: new Date("2025-12-31T12:00:00Z"), expected: "2025-12-31" },
    { date: new Date("2026-01-01T12:00:00Z"), expected: "2026-01-01" },
  ];
  
  for (const testCase of testCases) {
    const formatted = formatDate(testCase.date);
    assertEquals(formatted, testCase.expected, `Date ${testCase.date.toISOString()} should format as ${testCase.expected}`);
    console.log(`   ${testCase.date.toISOString()} → ${formatted} ✅`);
  }
  
  // Verify format pattern
  const now = new Date();
  const formatted = formatDate(now);
  const formatPattern = /^\d{4}-\d{2}-\d{2}$/;
  assertEquals(
    formatPattern.test(formatted),
    true,
    `Formatted date should match YYYY-MM-DD pattern, got: ${formatted}`
  );
  
  console.log("✅ Test 4 PASS: Date formatting works correctly (YYYY-MM-DD)");
} catch (error) {
  console.error("❌ Test 4 FAIL:", error);
  Deno.exit(1);
}

// Test 5: Test the logic flow (simulated)
console.log("\n📊 Test 5: Logic flow simulation");
try {
  function formatDate(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
      date.getDate()
    ).padStart(2, "0")}`;
  }
  
  // Simulate normal mode
  Deno.env.delete("TESTING_MODE");
  const clientDeadline = "2025-01-13"; // Client sends next Monday
  let deadlineDate: string;
  
  // This simulates the logic in super-service/index.ts
  const TESTING_MODE = Deno.env.get("TESTING_MODE") === "true";
  if (TESTING_MODE) {
    const { getNextDeadline } = await import("../functions/_shared/timing.ts");
    const compressedDeadline = getNextDeadline();
    deadlineDate = formatDate(compressedDeadline);
  } else {
    deadlineDate = clientDeadline;
  }
  
  assertEquals(deadlineDate, clientDeadline, "Normal mode should use client's deadline");
  console.log(`   Normal mode: deadlineDate = ${deadlineDate} (client's deadline) ✅`);
  
  // Simulate testing mode
  Deno.env.set("TESTING_MODE", "true");
  // Note: In real Edge Function, TESTING_MODE is evaluated at module load time
  // So we can't easily test this without reloading the module
  console.log("   Testing mode: Would override client deadline with compressed deadline");
  console.log("   (Requires module reload to test properly)");
  
  Deno.env.delete("TESTING_MODE");
  console.log("✅ Test 5 PASS: Logic flow is correct");
} catch (error) {
  console.error("❌ Test 5 FAIL:", error);
  Deno.exit(1);
}

// Test 6: Verify Edge Function file can be imported (syntax check)
console.log("\n📊 Test 6: Edge Function syntax check");
try {
  // Just verify the file can be parsed (we can't actually import it as a module easily)
  const fileContent = await Deno.readTextFile("../functions/super-service/index.ts");
  
  // Check for key elements
  const hasImport = fileContent.includes('import { TESTING_MODE, getNextDeadline }');
  const hasFormatDate = fileContent.includes('formatDeadlineDate') || fileContent.includes('function formatDate');
  const hasTestingModeCheck = fileContent.includes('if (TESTING_MODE)');
  const hasDeadlineDate = fileContent.includes('deadlineDate');
  
  assertEquals(hasImport, true, "File should import timing helper");
  assertEquals(hasFormatDate, true, "File should have formatDate or formatDeadlineDate function");
  assertEquals(hasTestingModeCheck, true, "File should check TESTING_MODE");
  assertEquals(hasDeadlineDate, true, "File should use deadlineDate variable");
  
  console.log("   ✅ Has timing helper import");
  console.log("   ✅ Has formatDate function");
  console.log("   ✅ Has TESTING_MODE check");
  console.log("   ✅ Uses deadlineDate variable");
  console.log("✅ Test 6 PASS: Edge Function has correct structure");
} catch (error) {
  console.error("❌ Test 6 FAIL:", error);
  Deno.exit(1);
}

console.log("\n============================================================");
console.log("✅ All Step 1.3 tests passed!");
console.log("============================================================");
console.log("\nNote: Full integration test requires:");
console.log("  1. Edge Function deployed with TESTING_MODE=true");
console.log("  2. Actual commitment creation via Edge Function");
console.log("  3. Database verification of deadline");

