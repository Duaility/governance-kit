import { createPool } from "./db";

export async function main() {
  const pool = createPool();
  await pool.query("SELECT 1");
  return "ok";
}
