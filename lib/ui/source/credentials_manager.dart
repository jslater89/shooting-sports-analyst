
import 'package:flutter/material.dart';
import 'package:shooting_sports_analyst/config/secure_config.dart';

class SourceCredentialsManager extends StatefulWidget {
  const SourceCredentialsManager({super.key});

  @override
  State<SourceCredentialsManager> createState() => _SourceCredentialsManagerState();
}

class _SourceCredentialsManagerState extends State<SourceCredentialsManager> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool obscure = true;

  @override
  void initState() {
    super.initState();
    _loadCredentials();
  }

  Future<void> _loadCredentials() async {
    var (username, password) = await SecureConfig.getPsCredentials();
    _usernameController.text = username ?? "";
    _passwordController.text = password ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Manage match source credentials"),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Some match sources require credentials to access their data. Credentials entered "
              "here will be stored in your operating system's secure storage, using encryption keys "
              "that are local to your computer. They will be used exclusively to authenticate with "
              "the match source in question.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            Divider(),
            Text("PractiScore web reports", style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: "Username",
                    ),
                    controller: _usernameController,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: "Password",
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () {
                          setState(() {
                            obscure = !obscure;
                          });
                        },
                      ),
                    ),
                    controller: _passwordController,
                    obscureText: obscure,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () async {
                    await SecureConfig.setPsUsername("");
                    await SecureConfig.setPsPassword("");
                    _usernameController.text = "";
                    _passwordController.text = "";
                  },
                ),
              ],
            ),
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
          child: Text("SAVE"),
          onPressed: () async {
            await SecureConfig.setPsUsername(_usernameController.text);
            await SecureConfig.setPsPassword(_passwordController.text);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
