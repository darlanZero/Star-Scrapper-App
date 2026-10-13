import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:star_scrapper_app/application/library/library_organization_contracts.dart';
import 'package:star_scrapper_app/application/library/tabs_state.dart';

class RecordingOrganizer implements LibraryOrganizationUpdater {
  final List<String> operations = [];

  @override
  void nestPrimaryAsSubTab(String oldPrimaryTab, String targetPrimary) {
    operations.add('nest:$oldPrimaryTab:$targetPrimary');
  }

  @override
  void remapBooksFromRemovedSubTab(
    String primaryTab,
    String removedSubTab,
    String defaultSubTab,
  ) {
    operations.add(
      'remove-sub:$primaryTab:$removedSubTab:$defaultSubTab',
    );
  }

  @override
  void remapBooksFromRemovedTab(String removedTab, String defaultTab) {
    operations.add('remove:$removedTab:$defaultTab');
  }

  @override
  void renamePrimaryTabBooks(String oldName, String newName) {
    operations.add('rename:$oldName:$newName');
  }

  @override
  void renameSubTabBooks(String primaryTab, String oldName, String newName) {
    operations.add('rename-sub:$primaryTab:$oldName:$newName');
  }
}

Future<TabsState> createTabsState() async {
  SharedPreferences.setMockInitialValues({
    'libraryTabs': ['Reading', 'Completed'],
    'librarySubTabsByPrimary': jsonEncode({
      'Reading': ['Unread', 'Read'],
      'Completed': ['Archived'],
    }),
  });
  final state = TabsState();
  await state.tabsLoaded;
  return state;
}

void main() {
  test('renames and removes tabs through the organization contract', () async {
    final state = await createTabsState();
    final organizer = RecordingOrganizer();

    state.renameLibraryTab(1, 'Finished', organizer);
    state.removeLibraryTab(1, organizer);

    expect(state.libraryTabs, ['Reading']);
    expect(organizer.operations, [
      'rename:Completed:Finished',
      'remove:Finished:Reading',
    ]);
  });

  test('nests a primary tab without depending on FontProvider', () async {
    final state = await createTabsState();
    final organizer = RecordingOrganizer();

    state.nestPrimaryTabAsSubTab(
      tabToNest: 'Completed',
      targetPrimary: 'Reading',
      organizer: organizer,
    );

    expect(state.libraryTabs, ['Reading']);
    expect(state.getSubTabsForPrimary('Reading'), contains('Completed'));
    expect(organizer.operations, ['nest:Completed:Reading']);
  });
}
