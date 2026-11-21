// Run repository Python tools on Windows and Unix without relying on the
// Windows Store's python3 App Execution Alias. Do not install Python or use a shell.
import { spawnSync } from 'node:child_process';

const args = process.argv.slice(2);
if (!args.length) {
  console.error('Usage: node scripts/run-python.mjs <script.py> [arguments]');
  process.exit(2);
}
const choices = process.platform === 'win32'
  ? [['py', ['-3', ...args]], ['python', args], ['python3', args]]
  : [['python3', args], ['python', args]];

for (const [command, argv] of choices) {
  const result = spawnSync(command, argv, { stdio: 'inherit', shell: false, windowsHide: true });
  if (result.error?.code === 'ENOENT') continue;
  if (result.error) {
    console.error('Could not launch ' + command + ': ' + result.error.message);
    process.exit(1);
  }
  if (result.signal) {
    console.error('Python process ended after signal: ' + result.signal);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}
console.error('Python 3 not found. On Windows install Python and enable the py launcher.');
process.exit(127);
