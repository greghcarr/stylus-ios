import SwiftUI

// Compact row used by the "All X" / "(no X)" sentinels across
// ArtistsView, AlbumsView, GenresView, AllArtistsView, and
// ArtistDetailView. The sentinels share the same shape -- 44 pt
// leading icon, italicised-or-plain title, count on the trailing
// edge -- so factoring them into one view both removes 12-ish
// inline HStack duplications AND lets the same view be used as
// the long-press preview content for those rows.
struct LibraryIconRow: View
{
    let icon:     String      // SF Symbol name
    let title:    String
    let count:    Int
    let italic:   Bool

    init(icon:    String,
         title:   String,
         count:   Int,
         italic:  Bool = false)
    {
        self.icon     = icon
        self.title    = title
        self.count    = count
        self.italic   = italic
    }

    var body: some View
    {
        HStack(spacing: 12)
        {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            italic
                ? Text(title).italic()
                : Text(title)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        // Make the entire row width hit-testable. Without this, the
        // Spacer in the middle is a hole in the Button's hit area
        // (Buttons hit-test their label's natural shape, which
        // excludes empty layout space), so taps that land between
        // the title and the count count as misses. NavigationLink
        // used to auto-extend tap to the full cell, but the row
        // wrappers are Buttons now.
        .contentShape(Rectangle())
    }
}

// And an analogous row for the per-X items that show a composite
// artwork thumbnail instead of an SF Symbol -- artists, genres,
// podcasts, playlists. Same shape minus the italic flag (those
// rows always render plain).
struct CompositeArtworkRow: View
{
    let representativePaths: [String]
    let title:               String
    let count:               Int

    var body: some View
    {
        HStack(spacing: 12)
        {
            CompositeArtworkThumb(representativePaths: representativePaths)
            Text(title).lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        // Make the entire row width hit-testable. Without this, the
        // Spacer in the middle is a hole in the Button's hit area
        // (Buttons hit-test their label's natural shape, which
        // excludes empty layout space), so taps that land between
        // the title and the count count as misses. NavigationLink
        // used to auto-extend tap to the full cell, but the row
        // wrappers are Buttons now.
        .contentShape(Rectangle())
    }
}

// Row for the "(no X)" sentinels (no artist, no album, no genre).
// Same shape as LibraryIconRow but the leading slot uses the same
// dashed-rounded-rectangle placeholder as CompositeArtworkThumb's
// empty state instead of an SF Symbol -- so every "no value for
// this category" cell across the app shows the same glyph.
// Title is always italic since this row type is reserved for
// untagged categories, never a real value.
struct LibraryDashedRow: View
{
    let title: String
    let count: Int

    var body: some View
    {
        HStack(spacing: 12)
        {
            DashedSquarePlaceholder()
            Text(title).italic()
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        // Make the entire row width hit-testable. Without this, the
        // Spacer in the middle is a hole in the Button's hit area
        // (Buttons hit-test their label's natural shape, which
        // excludes empty layout space), so taps that land between
        // the title and the count count as misses. NavigationLink
        // used to auto-extend tap to the full cell, but the row
        // wrappers are Buttons now.
        .contentShape(Rectangle())
    }
}
