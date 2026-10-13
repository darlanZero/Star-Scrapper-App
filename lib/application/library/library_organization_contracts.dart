/// Read-only tab configuration required by library organization rules.
abstract interface class LibraryTabConfiguration {
  List<String> get libraryTabs;

  List<String> getSubTabsForPrimary(String primaryTab);

  String getDefaultSubTabForPrimary(String primaryTab);
}

/// Operations needed when the user changes the tab hierarchy.
abstract interface class LibraryOrganizationUpdater {
  void renamePrimaryTabBooks(String oldName, String newName);

  void remapBooksFromRemovedTab(String removedTab, String defaultTab);

  void renameSubTabBooks(String primaryTab, String oldName, String newName);

  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  );

  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary);
}
