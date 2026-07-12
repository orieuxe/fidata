import AdmZip from "adm-zip";

export type RatingKind = "standard" | "rapid" | "blitz";

/** FIDE's archive URL pattern is uniform for every month back to Feb 2015. */
export function xmlZipUrl(kind: RatingKind, token: string): string {
  return `https://ratings.fide.com/download/${kind}_${token}frl_xml.zip`;
}

/** Downloads a month's zip and returns the raw XML text inside it, or null if not found (404). */
export async function fetchRatingXml(
  kind: RatingKind,
  token: string,
): Promise<string | null> {
  const url = xmlZipUrl(kind, token);
  const res = await fetch(url);
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${url} -> HTTP ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  const zip = new AdmZip(buf);
  const entry = zip.getEntries()[0];
  if (!entry) throw new Error(`${url} -> empty zip`);
  return entry.getData().toString("utf-8");
}
