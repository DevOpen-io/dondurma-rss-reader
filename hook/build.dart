import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

/// Compiles the lifecycle publication mutex for every native target. The
/// asset ID matches the `@DefaultAsset` of lib/services/lifecycle_mutex.dart.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    await CBuilder.library(
      name: 'lifecycle_mutex',
      assetName: 'services/lifecycle_mutex.dart',
      sources: ['native/lifecycle/lifecycle_mutex.c'],
      flags: [
        if (input.config.code.targetOS != OS.windows) ...['-Wall', '-Wextra'],
      ],
    ).run(input: input, output: output);
  });
}
