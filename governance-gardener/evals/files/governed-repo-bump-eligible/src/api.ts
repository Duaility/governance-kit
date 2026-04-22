export function getHealth(): { ok: boolean } {
  return { ok: true };
}

export function getVersion(): { version: string } {
  return { version: "0.1.0" };
}
