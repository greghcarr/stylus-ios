import SwiftUI

// 44 x 44 thumbnail that renders up to four album thumbnails in a
// 2 x 2 grid (one per representative path supplied by the caller).
// Used by every "group of tracks" row in the library: artists,
// genres, playlists, podcasts. Each list passes a small sample of
// representative file paths (one per distinct album for music
// surfaces, one per distinct episode for podcasts), capped at 8.
//
// Layout per artwork count after the async loads complete:
//   0  -> rounded-rect dashed-border placeholder (drawn ourselves
//         so the placeholder's rounded corners match the other
//         thumbnails the app renders)
//   1  -> single thumbnail fills the 44 x 44 slot
//   2  -> top-left + top-right (each 22 x 22), bottom row slots
//         are transparent so the row's natural background shows
//         through under the present artwork
//   3  -> top-left + top-right + bottom-left; bottom-right slot
//         transparent
//   4+ -> full 2 x 2 grid (extras beyond 4 are ignored)
//
// The dashed-border placeholder is shown both during the initial
// load AND when none of the representative paths produce artwork --
// the two states share the same look so the row never visibly
// flickers between "loading" and "no art".
struct CompositeArtworkThumb: View
{
    let representativePaths: [String]

    @State private var artworks: [UIImage] = []

    var body: some View
    {
        artworkSlot
            .task(id: representativePaths)
            {
                await loadArtworks()
            }
    }

    @ViewBuilder
    private var artworkSlot: some View
    {
        Group
        {
            if artworks.isEmpty
            {
                // Same dashed-rounded-rectangle placeholder used by
                // every "(no X)" row across the app -- defined in
                // DashedSquarePlaceholder so the look is identical
                // everywhere it shows up.
                DashedSquarePlaceholder()
            }
            else if artworks.count == 1
            {
                Image(uiImage: artworks[0])
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            else
            {
                gridLayout
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var gridLayout: some View
    {
        VStack(spacing: 0)
        {
            HStack(spacing: 0)
            {
                slot(0)
                slot(1)
            }
            HStack(spacing: 0)
            {
                slot(2)
                slot(3)
            }
        }
    }

    @ViewBuilder
    private func slot(_ index: Int) -> some View
    {
        if index < artworks.count
        {
            Image(uiImage: artworks[index])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 22, height: 22)
                .clipped()
        }
        else
        {
            // Empty slots in the 2 / 3 artwork composites are
            // transparent rather than placeholder-filled, so the
            // row's natural background shows through underneath
            // the present artworks.
            Color.clear.frame(width: 22, height: 22)
        }
    }

    // Walk representativePaths in order, keep the first 4 that
    // produce a non-nil thumbnail. ArtworkCache short-circuits
    // already-decoded entries so subsequent paint passes are
    // essentially free; only the first scroll through pays the
    // decode cost.
    private func loadArtworks() async
    {
        var loaded: [UIImage] = []
        for path in representativePaths
        {
            if loaded.count >= 4 { break }
            if let img = await loadThumbnail(for: path)
            {
                loaded.append(img)
            }
        }
        artworks = loaded
    }
}

// 44 pt dashed-rounded-rectangle placeholder. Used as the "no
// artwork" / "no value for this category" glyph everywhere it
// appears (CompositeArtworkThumb's empty state, and the leading
// slot of every "(no album)" / "(no artist)" / "(no genre)" row).
// The dashed border is drawn ourselves rather than via the
// SF Symbol `square.dashed` so the corners are rounded to match
// the surrounding thumbnails.
struct DashedSquarePlaceholder: View
{
    // Slot the placeholder lives in (44 pt to match the artwork
    // thumbnails it sits beside). The visible dashed rectangle is
    // inset 6 pt so it reads as smaller than the slot, matching
    // iTunes' "smaller silhouette" placeholder convention rather
    // than a heavy edge-to-edge box.
    var size:  CGFloat = 44
    var inset: CGFloat = 6

    var body: some View
    {
        RoundedRectangle(cornerRadius: 3)
            .strokeBorder(
                Color.secondary,
                style: StrokeStyle(lineWidth: 2, dash: [3, 3])
            )
            .padding(inset)
            .frame(width: size, height: size)
    }
}
