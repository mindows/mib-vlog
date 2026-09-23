# Contributing

Issues and pull requests are welcome. Every change lands through a pull
request that the maintainer reviews and merges; nobody pushes to `main`
directly.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/mindows/mib-vlog/issues/new/choose) and
pick the template that fits. For bugs, the shell log is the most useful
thing to include:

```bash
qs log -p /usr/share/omarchy/shell | grep -i mib-vlog
```

## Working on the plugin

1. Fork the repo and clone your fork.
2. Point Omarchy at your clone instead of an installed copy:

   ```bash
   ln -sfn "$PWD" ~/.config/omarchy/plugins/mib-vlog
   omarchy plugin enable mib-vlog
   ```

3. After each change, restart the shell with `omarchy-restart-shell`.
   `omarchy-shell shell rescanPlugins` can keep serving the cached copy of
   files it has already loaded, so it is not a reliable way to see an edit.
4. Check your work before opening the pull request:

   ```bash
   omarchy plugin validate .
   /usr/lib/qt6/bin/qmllint *.qml
   bash -n *.sh
   ```

## Style

- Match the code around your change: its naming, layout, and how much it
  comments. Comments say why, in plain sentences.
- Keep the README in step with behaviour. A new setting, requirement, or
  change to what a take contains belongs in it.
- Commit messages: a short imperative subject ("Add a Mirror video
  setting"), then a body that explains what changed and why.
- One topic per pull request.

## Privacy

The plugin sees a camera, a microphone, and the user's location. Changes
that send any of that anywhere new, or write it into files, need to say so
in the pull request and the README, and should be off by default.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
