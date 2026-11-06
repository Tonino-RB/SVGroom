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

@Test func syncTagsCopiesAgreedTagsAndReportsConflicts() {
    let group = ["/x/a", "/x/b", "/x/c"]
    let tags: [String: Int?] = [
        "/x/a/1.svg": 3, "/x/b/1.svg": nil, "/x/c/1.svg": 3,     // agreed → copied to b
        "/x/a/2.svg": nil, "/x/b/2.svg": nil,                    // nothing to copy
        "/x/a/s/3.svg": 1, "/x/b/s/3.svg": 2, "/x/c/s/3.svg": nil, // conflict
        "/x/b/4.svg": 5, "/x/c/4.svg": nil,                      // missing in a
        "/y/1.svg": 4,                                           // outside the group
    ]
    let sync = FolderLinks.syncTags(in: group, tags: tags)
    #expect(sync.copies == ["/x/b/1.svg": 3, "/x/c/4.svg": 5])
    #expect(sync.conflicts == [["/x/a/s/3.svg", "/x/b/s/3.svg", "/x/c/s/3.svg"]])
}

@Test func firstVersionsKeepsOneFilePerRelativePath() {
    let groups = [["/x/a", "/x/b"]]
    let paths = ["/x/a/1.svg", "/x/b/1.svg", "/x/b/2.svg", "/x/a/s/3.svg", "/x/a/2.svg", "/x/b/s/3.svg", "/y/1.svg", "/x/c/1.svg"]
    #expect(FolderLinks.firstVersions(paths, in: groups) == [0, 2, 3, 6, 7])
    #expect(FolderLinks.firstVersions(paths, in: []) == Array(paths.indices))
}
