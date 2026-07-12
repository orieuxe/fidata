export function fideProfileUrl(fideid: number) {
  return `https://ratings.fide.com/profile/${fideid}`;
}

// Lichess doesn't validate the name slug, but building it right keeps links tidy.
// "Lastname, Firstname" -> "Lastname_Firstname"
export function lichessUrl(fideid: number, name: string) {
  const slug = name.replace(", ", "_").replace(/ /g, "_");
  return `https://lichess.org/fide/${fideid}/${slug}`;
}
