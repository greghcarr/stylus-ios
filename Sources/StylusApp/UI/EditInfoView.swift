import SwiftUI

// Per-track metadata editor. Form-based: title / artist / album / genre /
// year / track #. The "Look up on iTunes" button kicks the bridged
// AppleMusicLookup with the currently-edited values as query hints; when
// the result lands the form repopulates from the freshly-updated Track.
// "Save" persists via Stylus_StylSave (which preserves disk-side fields
// the user didn't touch, like playCount and dateAdded).
struct EditInfoView: View
{
    let trackPath: String

    @Environment(\.dismiss)        private var dismiss
    @EnvironmentObject             var library: LibraryStore
    @EnvironmentObject             var lookup:  LookupController

    @State private var title:       String = ""
    @State private var artist:      String = ""
    @State private var album:       String = ""
    @State private var genre:       String = ""
    @State private var year:        String = ""
    @State private var trackNumber: Int    = 0
    @State private var lookingUp:   Bool   = false

    var body: some View
    {
        NavigationStack
        {
            Form
            {
                Section("Track")
                {
                    TextField("Title",  text: $title)
                    TextField("Artist", text: $artist)
                    TextField("Album",  text: $album)
                }

                Section("Details")
                {
                    TextField("Genre", text: $genre)
                    TextField("Year",  text: $year).keyboardType(.numberPad)
                    Stepper("Track #: \(trackNumber)", value: $trackNumber, in: 0 ... 999)
                }

                Section
                {
                    Button
                    {
                        performLookup()
                    }
                    label:
                    {
                        HStack
                        {
                            Label("Look up on iTunes",
                                  systemImage: "magnifyingglass")
                            Spacer()
                            if lookingUp
                            {
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(lookingUp)
                }
            }
            .navigationTitle("Edit Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar
            {
                ToolbarItem(placement: .cancellationAction)
                {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction)
                {
                    Button("Save")
                    {
                        save()
                    }
                }
            }
            .onAppear { populateFromLibrary() }
            .onChange(of: library.tracks)
            {
                if lookingUp
                {
                    populateFromLibrary()
                    lookingUp = false
                }
            }
        }
    }

    private func populateFromLibrary()
    {
        guard let t = library.tracks.first(where: { $0.filePath == trackPath })
        else { return }
        title       = t.title
        artist      = t.artist
        album       = t.album
        genre       = t.genre
        year        = t.year
        trackNumber = t.trackNumber
    }

    private func performLookup()
    {
        guard let original = library.tracks.first(where: { $0.filePath == trackPath })
        else { return }
        // Use currently-edited fields as the query hint so a user-corrected
        // artist / title gets a better iTunes match than the original tag.
        let hint = Track(
            filePath:        original.filePath,
            title:           title,
            artist:          artist,
            album:           album,
            genre:           genre,
            year:            year,
            trackNumber:     trackNumber,
            bpm:             original.bpm,
            key:             original.key,
            durationSeconds: original.durationSeconds,
            isPodcast:       original.isPodcast,
            podcast:         original.podcast
        )
        lookup.enqueue(hint, overwrite: true)
        lookingUp = true
    }

    private func save()
    {
        guard let original = library.tracks.first(where: { $0.filePath == trackPath })
        else { dismiss(); return }
        let edited = Track(
            filePath:        original.filePath,
            title:           title,
            artist:          artist,
            album:           album,
            genre:           genre,
            year:            year,
            trackNumber:     trackNumber,
            bpm:             original.bpm,
            key:             original.key,
            durationSeconds: original.durationSeconds,
            isPodcast:       original.isPodcast,
            podcast:         original.podcast
        )
        library.save(edited)
        dismiss()
    }
}
