protocol WorkspaceDelegate {
    var workspace: Odyssey.Workspace { get }

    func toggleLeftPane()
    func toggleRightPane()
    func markForRestoration()
}
