export function createPool() {
  return {
    query: async (_sql: string) => ({ rows: [] }),
  };
}
