import { XMLParser } from "fast-xml-parser";

export interface PlayerRow {
  fideid: number;
  name: string;
  country: string | null;
  sex: string | null;
  title: string | null;
  w_title: string | null;
  o_title: string | null;
  birthday: number | null;
  rating: number | null;
  games: number | null;
  k: number | null;
  flag: string | null;
}

const parser = new XMLParser({
  isArray: (name) => name === "player",
});

function toIntOrNull(v: unknown): number | null {
  if (v === undefined || v === null || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function toStrOrNull(v: unknown): string | null {
  if (v === undefined || v === null || v === "") return null;
  return String(v);
}

export function parsePlayers(xml: string): PlayerRow[] {
  const doc = parser.parse(xml);
  const players = doc.playerslist?.player ?? [];
  return players.map((p: Record<string, unknown>) => ({
    fideid: Number(p.fideid),
    name: String(p.name),
    country: toStrOrNull(p.country),
    sex: toStrOrNull(p.sex),
    title: toStrOrNull(p.title),
    w_title: toStrOrNull(p.w_title),
    o_title: toStrOrNull(p.o_title),
    birthday: toIntOrNull(p.birthday),
    rating: toIntOrNull(p.rating),
    games: toIntOrNull(p.games),
    k: toIntOrNull(p.k),
    flag: toStrOrNull(p.flag),
  }));
}
