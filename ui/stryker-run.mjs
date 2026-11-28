// Runs Stryker with the options in stryker.config.json, plus a breaking threshold from the command line:
//
//   node stryker-run.mjs --thresholds.break <percent>
//
// The Stryker CLI has no flag for thresholds, so this sets `thresholds.break` through the Stryker API. The
// threshold is not kept in the config file: the factory passes its mutation minimum each run.
import { Stryker } from '@stryker-mutator/core';

const args = process.argv.slice(2);
const flag = args.indexOf('--thresholds.break');
const value = flag === -1 ? Number.NaN : Number(args[flag + 1]);
if (!Number.isFinite(value) || value < 0 || value > 100) {
  console.error('Usage: node stryker-run.mjs --thresholds.break <percent from 0 to 100>');
  process.exit(2);
}

const stryker = new Stryker({ thresholds: { high: value, low: value, break: value } });
await stryker.runMutationTest();
