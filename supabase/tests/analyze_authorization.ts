/**
 * Analyze authorization calculation for specific parameters
 */

// User's parameters
const limitMinutes = 1;
const penaltyPerMinuteCents = 20; // $0.20 per minute
const appCount = 1; // Assuming 1 app
const daysRemaining = 7; // Full week

console.log("📊 Authorization Calculation Analysis");
console.log("====================================");
console.log(`Limit: ${limitMinutes} minute(s)`);
console.log(`Penalty: $${(penaltyPerMinuteCents / 100).toFixed(2)} per minute`);
console.log(`Apps: ${appCount}`);
console.log(`Days Remaining: ${daysRemaining}`);
console.log("");

// Step-by-step calculation (matching the SQL formula)
const maxUsageMinutes = Math.min(7, daysRemaining) * 720; // 12 hours/day, cap at 7 days
console.log(`1. Max Usage: ${maxUsageMinutes} minutes (${(maxUsageMinutes / 60).toFixed(1)} hours)`);
console.log(`   Assumes: 12 hours/day × ${Math.min(7, daysRemaining)} days`);

const potentialOverageMinutes = Math.max(0, maxUsageMinutes - limitMinutes);
console.log(`2. Potential Overage: ${potentialOverageMinutes} minutes`);
console.log(`   = Max Usage (${maxUsageMinutes}) - Limit (${limitMinutes})`);

const strictnessRatio = maxUsageMinutes / Math.max(1, limitMinutes);
console.log(`3. Strictness Ratio: ${strictnessRatio.toFixed(2)}`);
console.log(`   = Max Usage (${maxUsageMinutes}) / Limit (${limitMinutes})`);

const strictnessMultiplier = Math.min(10.0, strictnessRatio * 0.4); // Capped at 10x
console.log(`4. Strictness Multiplier: ${strictnessMultiplier.toFixed(2)}x (capped at 10x)`);
console.log(`   = min(10.0, Strictness Ratio (${strictnessRatio.toFixed(2)}) × 0.4)`);

let baseAmountCents = potentialOverageMinutes * penaltyPerMinuteCents * strictnessMultiplier;
console.log(`5. Base Amount (before factors): $${(baseAmountCents / 100).toFixed(2)}`);
console.log(`   = Overage (${potentialOverageMinutes}) × Penalty (${penaltyPerMinuteCents}¢) × Multiplier (${strictnessMultiplier.toFixed(2)}x)`);

const riskFactor = 1.0 + ((Math.max(1, appCount) - 1) * 0.02);
console.log(`6. Risk Factor: ${riskFactor.toFixed(2)}x`);
console.log(`   = 1.0 + ((${appCount} - 1) × 0.02)`);

const timeFactor = 1.0 + (Math.min(7, daysRemaining) / 7.0 * 0.2);
console.log(`7. Time Factor: ${timeFactor.toFixed(2)}x`);
console.log(`   = 1.0 + (${Math.min(7, daysRemaining)} / 7 × 0.2)`);

baseAmountCents = baseAmountCents * riskFactor * timeFactor;
console.log(`8. After Risk & Time Factors: $${(baseAmountCents / 100).toFixed(2)}`);

const dampingFactor = 0.026;
baseAmountCents = baseAmountCents * dampingFactor;
console.log(`9. After Damping (× 0.026): $${(baseAmountCents / 100).toFixed(2)}`);
console.log(`   Damping accounts for users not actually using apps 12h/day every day`);

const minCents = 1500; // $15
const maxCents = 100000; // $1000
const finalCents = Math.max(minCents, Math.min(maxCents, Math.floor(baseAmountCents)));
console.log(`10. Final (capped at $${(minCents/100).toFixed(2)} - $${(maxCents/100).toFixed(2)}): $${(finalCents / 100).toFixed(2)}`);
console.log("");

console.log("🔍 Analysis:");
console.log("===========");
console.log(`With a ${limitMinutes}-minute limit:`);
console.log(`- The strictness ratio is ${strictnessRatio.toFixed(0)}x (extremely high)`);
console.log(`- This creates a strictness multiplier of ${strictnessMultiplier.toFixed(0)}x`);
console.log(`- Even with damping, the calculation exceeds $${(maxCents/100).toFixed(2)}, so it gets capped`);
console.log("");
console.log("💡 The Problem:");
console.log("The formula assumes worst-case usage (12h/day for 7 days = 5,040 minutes)");
console.log(`With a ${limitMinutes}-minute limit, the potential overage is ${potentialOverageMinutes} minutes`);
console.log(`This extreme strictness (${strictnessRatio.toFixed(0)}x ratio) drives the authorization to the $${(maxCents/100).toFixed(2)} cap`);
console.log("");
console.log("✅ Your Calculation:");
const realisticOverage = 30 * 60; // 30 hours = 1,800 minutes
const realisticPenalty = realisticOverage * penaltyPerMinuteCents;
console.log(`If someone uses 30 hours over limit: ${realisticOverage} minutes × $${(penaltyPerMinuteCents/100).toFixed(2)} = $${(realisticPenalty/100).toFixed(2)}`);
console.log(`This is much less than the $${(maxCents/100).toFixed(2)} authorization`);
console.log("");
console.log("📝 Suggested Fix:");
console.log("The formula needs to handle very strict limits (like 1 minute) differently.");
console.log("Options:");
console.log("1. Cap the strictness multiplier (e.g., max 10x instead of unlimited)");
console.log("2. Use a different formula for very strict limits (< 60 minutes)");
console.log("3. Base authorization on a more realistic worst-case (e.g., 24 hours overage max)");

