import 'package:flutter/material.dart';

class ShooterAliasesDialog extends StatefulWidget {
  const ShooterAliasesDialog(this.initialAliases, {Key? key}) : super(key: key);

  final Map<String, String> initialAliases;
  
  @override
  State<ShooterAliasesDialog> createState() => _ShooterAliasesDialogState();
}

class _ShooterAliasesDialogState extends State<ShooterAliasesDialog> {
  late List<_Alias> aliases;

  TextEditingController _aliasController = TextEditingController();
  TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();

    aliases = widget.initialAliases.keys.map((e) => _Alias(e, widget.initialAliases[e]!)).toList();
  }

  String _errorText = "";
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Edit Shooter Aliases"),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 600,
          maxWidth: 800,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Enter shooter aliases in lowercase without spaces. For example, enter 'Max Michel Jr.' as 'maxmicheljr.'.\n\n"
                "Aliases are only necessary when a shooter switches to a lifetime "
                "member number, and the name he registered with at the first match using his "
                "lifetime member number differs from the name he registered with at his first "
                "match in the dataset.", style: Theme.of(context).textTheme.bodyText2),
            SizedBox(height: 5),
            Text(_errorText, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).errorColor)),
            SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text("This name is the same shooter..."),
                ),
                Expanded(
                  flex: 4,
                  child: Text("...as this name"),
                ),
                Expanded(
                  flex: 1,
                  child: Container(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: TextField(
                      controller: _aliasController,
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: TextField(
                      controller: _nameController,
                    ),
                  )
                ),
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: Icon(Icons.add),
                    onPressed: () {
                      _addAlias();
                    },
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _buildAliasRows(),
                ),
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text("CANCEL"),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        TextButton(
          child: Text("OK"),
          onPressed: () {
            Map<String, String> aliasMap = Map.fromEntries(
              aliases.map((a) => MapEntry<String, String>(a.alias, a.name))
            );
            Navigator.of(context).pop(aliasMap);
          },
        )
      ],
    );
  }

  List<Widget> _buildAliasRows() {
    List<Widget> widgets = [];
    for(int i = 0; i < aliases.length; i++) {
      widgets.add(_buildAliasRow(i));
    }
    return widgets;
  }

  String _processText(String text) {
    return text.toLowerCase().replaceAll(RegExp(r"\s+"), "");
  }

  void _addAlias() {
    var processedAlias = _processText(_aliasController.text);
    var processedName = _processText(_nameController.text);

    if(processedAlias.isEmpty || processedName.isEmpty) {
      setState(() {
        _errorText = "Enter both an alias and a name.";
      });
      return;
    }

    var hasAlias = false;
    for(var a in aliases) {
      if(processedAlias == a.alias) {
        hasAlias = true;
        break;
      }
    }

    if(hasAlias) {
      setState(() {
        _errorText = "$processedAlias already has a mapping.";
      });
      return;
    }
    else {
      setState(() {
        _errorText = "";
      });
    }

    setState(() {
      aliases.add(_Alias(
        _processText(processedAlias),
        _processText(processedName),
      ));
    });
    _aliasController.text = "";
    _nameController.text = "";
  }

  Widget _buildAliasRow(int index) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(aliases[index].alias),
          ),
        ),
        Expanded(
          flex: 4,
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Text(aliases[index].name),
          ),
        ),
        Expanded(
          flex: 1,
          child: IconButton(
            icon: Icon(Icons.delete),
            onPressed: () {
              setState(() {
                aliases.removeAt(index);
              });
            },
          ),
        ),
      ],
    );
  }
}

class _Alias {
  final String alias;
  final String name;

  _Alias(this.alias, this.name);
}
