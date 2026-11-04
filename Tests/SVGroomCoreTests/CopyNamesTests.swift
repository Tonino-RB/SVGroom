import Testing
@testable import SVGroomCore

@Test func copyNamesArePrefixedWithTheirFolder() {
    #expect(CopyNames.names(for: ["/x/coral/a.svg", "/x/reef/a.svg", "/x/reef/b.svg"])
        == ["coral_a.svg", "reef_a.svg", "reef_b.svg"])
}

@Test func copyNamesGoUpUntilDifferent() {
    // Linked folders: same structure, different top folder.
    #expect(CopyNames.names(for: ["/x/f1/coral/a.svg", "/x/f15/coral/a.svg", "/x/f1/coral/b.svg"])
        == ["f1_coral_a.svg", "f15_coral_a.svg", "coral_b.svg"])
}

@Test func copyNamesAvoidTakenNamesIgnoringCase() {
    #expect(CopyNames.names(for: ["/x/coral/a.svg"], taken: ["Coral_A.svg", "coral_a 2.svg"]) == ["coral_a 3.svg"])
}
