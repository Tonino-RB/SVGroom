import Testing
@testable import SVGroomCore

@Test func counterpartsByRelativePath() {
    let groups = [["/x/f03", "/x/f1", "/x/f15"]]
    #expect(FolderLinks.counterparts(of: "/x/f1/coral/a.svg", in: groups) == ["/x/f03/coral/a.svg", "/x/f15/coral/a.svg"])
    #expect(FolderLinks.counterparts(of: "/x/f10/a.svg", in: groups).isEmpty) // prefix of a name is not a match
    #expect(FolderLinks.counterparts(of: "/y/a.svg", in: groups).isEmpty)
}

@Test func linkMergesGroupsAndIgnoresNesting() {
    var groups = FolderLinks.link("/x/a", with: ["/x/b", "/x/a", "/x/a/sub", "/x"], in: [])
    #expect(groups == [["/x/a", "/x/b"]])
    groups = FolderLinks.link("/x/c", with: ["/x/d"], in: groups)
    #expect(groups.count == 2)
    groups = FolderLinks.link("/x/b", with: ["/x/d"], in: groups)
    #expect(groups == [["/x/a", "/x/b", "/x/c", "/x/d"]])
}

@Test func unlinkDropsSingletons() {
    let groups = FolderLinks.unlink("/x/a", in: [["/x/a", "/x/b"], ["/x/c", "/x/d", "/x/e"]])
    #expect(groups == [["/x/c", "/x/d", "/x/e"]])
}
