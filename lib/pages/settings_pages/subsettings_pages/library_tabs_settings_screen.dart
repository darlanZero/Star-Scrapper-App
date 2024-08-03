import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:star_scrapper_app/classes/app_state.dart';

class LibraryTabsSettingsScreen extends StatefulWidget {
  const LibraryTabsSettingsScreen({super.key});

  @override
  State<LibraryTabsSettingsScreen> createState() => _LibraryTabsSettingsScreenState();
}

class _LibraryTabsSettingsScreenState extends State<LibraryTabsSettingsScreen> {
  TextEditingController _textcontroller = TextEditingController();


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Color.fromARGB(29, 60, 16, 180),
        title: Text(
          "Library Tabs Settings",
          style: TextStyle(
            color: Color.fromARGB(255, 224, 224, 224),
            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
            fontWeight: FontWeight.bold,
          )
        ),
        centerTitle: true,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.teal[900]
            ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 224, 224, 224)),
      ),

      body: Consumer<TabsState>(
        builder: (context, tabsState, child) {
          return Column(
            children: [
              Expanded(
                child: ReorderableListView(
                  onReorder: (oldIndex, newIndex) {
                    tabsState.reorderLibraryTabs(oldIndex, newIndex);
                  },

                  children: [
                    for (int index = 0; index < tabsState.libraryTabs.length; index++)
                      ListTile(
                        key: ValueKey(tabsState.libraryTabs[index]),
                        title: Text(
                          tabsState.libraryTabs[index],
                          style: TextStyle(
                            color: Color.fromARGB(255, 224, 224, 224),
                            fontSize: MediaQuery.of(context).size.width >= 600 ? 24 : 18,
                            fontWeight: FontWeight.bold,
                          )
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete),
                          onPressed: () {
                            tabsState.removeLibraryTab(index);
                          },
                        ),
                        onTap: () async {
                          final newName = await _showRenameDialog(context, tabsState.libraryTabs[index]);
                          if (newName != null) {
                            tabsState.renameLibraryTab(index, newName);
                          }
                        },
                      )
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textcontroller,
                        decoration:  InputDecoration(
                          hintText: 'Add new tab name',
                          hintStyle: TextStyle(
                            color: Color.fromARGB(255, 224, 224, 224),
                          ),
                          filled: true,
                          fillColor: Colors.grey[800],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        style: TextStyle(
                          color: Color.fromARGB(255, 224, 224, 224),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.add, color: Colors.green,),
                      onPressed: () {
                        if (_textcontroller.text.isNotEmpty) {
                          tabsState.addLibraryTab(_textcontroller.text);
                          _textcontroller.clear();
                        }
                      },
                    )
                  ],
                ),
              )
            ],
          );
        }
      ),
    );
  }
}

Future<String?> _showRenameDialog(BuildContext context, String currentTabName) {
  final TextEditingController _controller = TextEditingController();
  _controller.text = currentTabName;

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Rename Tab'),
        content: TextField(
          controller: _controller,
          decoration: const InputDecoration(hintText: 'Enter new tab name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}