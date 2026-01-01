/**
 * Manual Test Script for Timing Helper (Step 1.1)
 * 
 * Quick verification that timing helper works correctly
 * 
 * Usage:
 *   TESTING_MODE=true deno run --allow-env test_timing_manual.ts
 *   deno run --allow-env test_timing_manual.ts
 */

import { 
  TESTING_MODE, 
  WEEK_DURATION_MS, 
  GRACE_PERIOD_MS, 
  getNextDeadline, 
  getGraceDeadline 
} from "../functions/_shared/timing.ts";

console.log("📊 Timing Helper Test (Step 1.1)");
console.log("================================\n");

console.log(`TESTING_MODE: ${TESTING_MODE}`);
console.log(`WEEK_DURATION_MS: ${WEEK_DURATION_MS} (${WEEK_DURATION_MS / 1000 / 60} minutes)`);
console.log(`GRACE_PERIOD_MS: ${GRACE_PERIOD_MS} (${GRACE_PERIOD_MS / 1000 / 60} minutes)`);
console.log("");

const now = new Date();
const deadline = getNextDeadline(now);
const graceDeadline = getGraceDeadline(deadline);

console.log(`Now: ${now.toISOString()}`);
console.log(`Next Deadline: ${deadline.toISOString()}`);
console.log(`Grace Deadline: ${graceDeadline.toISOString()}`);
console.log("");

const deadlineDiff = (deadline.getTime() - now.getTime()) / 1000 / 60;
const graceDiff = (graceDeadline.getTime() - deadline.getTime()) / 1000 / 60;

console.log(`Deadline is ${deadlineDiff.toFixed(2)} minutes from now`);
console.log(`Grace period is ${graceDiff.toFixed(2)} minutes after deadline`);
console.log("");

if (TESTING_MODE) {
  console.log("✅ Testing Mode: Expected ~3 min deadline, ~1 min grace");
  const deadlineOk = Math.abs(deadlineDiff - 3) < 0.1;
  const graceOk = Math.abs(graceDiff - 1) < 0.1;
  
  if (deadlineOk && graceOk) {
    console.log("✅ PASS: Timings match expected compressed values");
  } else {
    console.log("❌ FAIL: Timings don't match expected values");
    if (!deadlineOk) {
      console.log(`   Deadline: Expected ~3 min, got ${deadlineDiff.toFixed(2)} min`);
    }
    if (!graceOk) {
      console.log(`   Grace: Expected ~1 min, got ${graceDiff.toFixed(2)} min`);
    }
  }
} else {
  console.log("✅ Normal Mode: Expected next Monday deadline, 24h grace");
  console.log("   (Manual verification: Check that deadline is next Monday 12:00 ET)");
  console.log(`   Deadline day of week: ${deadline.getDay()} (0=Sun, 1=Mon, etc.)`);
  console.log(`   Deadline hour: ${deadline.getHours()}`);
  
  // graceDiff is in minutes, 24 hours = 1440 minutes
  if (graceDiff >= 1439 && graceDiff <= 1441) {
    console.log("✅ PASS: Grace period is ~24 hours (1440 minutes)");
  } else {
    console.log(`❌ FAIL: Grace period should be ~24 hours (1440 min), got ${graceDiff.toFixed(2)} minutes`);
  }
}

console.log("\n================================\n");

