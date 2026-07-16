protocol WorkspaceDelegate {
    var workspace: Odyssey.Workspace { get }

    func toggleLeftDock()
    func toggleRightDock()
    func markForRestoration()
}
