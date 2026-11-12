import { defineConfig } from 'vitest/config';

// Angular runs spec files without isolation by default, so files sharing a worker share modules and
// a vi.mock (e.g. of aws-amplify) in one cannot replace a module another already loaded. Which files
// share a worker depends on the machine's cores, so the tests passed locally but failed in CI.
export default defineConfig({ test: { isolate: true } });
