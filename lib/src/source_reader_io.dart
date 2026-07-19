import 'dart:io';

Map<String, Object?>? readSourceExcerpt(
  String file,
  int? line, {
  required String? rootDirectory,
  required Map<String, String> packageSourceRoots,
}) {
  if (line == null || line < 1) return null;
  final path = _resolvePath(file, rootDirectory, packageSourceRoots);
  if (path == null) return null;

  try {
    final sourceFile = File(path);
    if (!sourceFile.existsSync()) return null;
    final allLines = sourceFile.readAsLinesSync();
    if (line > allLines.length) return null;
    final startLine = line - 6 < 1 ? 1 : line - 6;
    final endLine = line + 6 > allLines.length ? allLines.length : line + 6;
    final lines = allLines
        .sublist(startLine - 1, endLine)
        .map((value) => value.length > 400 ? value.substring(0, 400) : value)
        .toList(growable: false);
    return <String, Object?>{'start_line': startLine, 'lines': lines};
  } catch (_) {
    return null;
  }
}

String? _resolvePath(
  String file,
  String? rootDirectory,
  Map<String, String> packageSourceRoots,
) {
  if (file.startsWith('package:')) {
    final value = file.substring('package:'.length);
    final separator = value.indexOf('/');
    if (separator < 1) return null;
    final package = value.substring(0, separator);
    final sourceRoot = packageSourceRoots[package];
    if (sourceRoot == null || sourceRoot.isEmpty) return null;
    return _join(sourceRoot, value.substring(separator + 1));
  }

  if (file.startsWith('file:')) {
    try {
      return Uri.parse(file).toFilePath();
    } catch (_) {
      return null;
    }
  }

  if (file.startsWith('/')) return file;
  if (rootDirectory == null || rootDirectory.isEmpty) return null;
  return _join(rootDirectory, file);
}

String _join(String root, String child) {
  final separator = Platform.pathSeparator;
  final cleanRoot = root.endsWith(separator)
      ? root.substring(0, root.length - separator.length)
      : root;
  final cleanChild =
      child.startsWith(separator) ? child.substring(separator.length) : child;
  return '$cleanRoot$separator$cleanChild';
}
