import SwiftUI

extension View
{
    // Hides the top edge of a list row when `isFirst` is true.
    // Apply to every row of a ForEach (passing index == 0) to
    // suppress the divider plain List otherwise draws above the
    // very first row. .listSectionSeparator(.hidden) is supposed
    // to handle this but doesn't reliably on iOS 26, so we hide
    // the row's top edge directly.
    //
    // For non-first rows we pass .automatic so the system's
    // default between-rows separator stays visible.
    func hideFirstRowSeparator(_ isFirst: Bool) -> some View
    {
        listRowSeparator(isFirst ? .hidden : .automatic, edges: .top)
    }
}
