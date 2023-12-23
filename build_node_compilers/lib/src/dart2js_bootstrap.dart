// Copyright (c) 2018, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
import 'package:crypto/crypto.dart';
import 'package:node_preamble/preamble.dart';
import 'package:path/path.dart' as p;
import 'package:scratch_space/scratch_space.dart';

import 'node_entrypoint_builder.dart';
import 'platforms.dart';

Future<void> bootstrapDart2Js(
    BuildStep buildStep, List<String> dart2JsArgs) async {
  final dartEntrypointId = buildStep.inputId;
  final moduleId =
      dartEntrypointId.changeExtension(moduleExtension(dart2jsPlatform));
  final args = <String>[];
  {
    final module = Module.fromJson(
        json.decode(await buildStep.readAsString(moduleId))
            as Map<String, Object?>);
    List<Module> allDeps;
    try {
      allDeps = (await module.computeTransitiveDependencies(buildStep))
        ..add(module);
    } on UnsupportedModules catch (e) {
      final librariesString = (await e.exactLibraries(buildStep).toList())
          .map((lib) => AssetId(lib.id.package,
              lib.id.path.replaceFirst(moduleLibraryExtension, '.dart')))
          .join('\n');
      log.warning('''
Skipping compiling ${buildStep.inputId} with dart2js because some of its
transitive libraries have sdk dependencies that not supported on this platform:

$librariesString

https://github.com/dart-lang/build/blob/master/docs/faq.md#how-can-i-resolve-skipped-compiling-warnings
''');
      return;
    }

    final scratchSpace = await buildStep.fetchResource(scratchSpaceResource);
    final allSrcs = allDeps.expand((module) => module.sources);
    await scratchSpace.ensureAssets(allSrcs, buildStep);
    final packageFile =
        await _createPackageFile(allSrcs, buildStep, scratchSpace);

    final dartPath = dartEntrypointId.path.startsWith('lib/')
        ? 'package:${dartEntrypointId.package}/'
            '${dartEntrypointId.path.substring('lib/'.length)}'
        : dartEntrypointId.path;
    final jsOutputPath =
        '${p.withoutExtension(dartPath.replaceFirst('package:', 'packages/'))}'
        '$jsEntrypointExtension';
    args.addAll(
      dart2JsArgs
        ..addAll(
          [
            '--packages=$packageFile',
            '-o$jsOutputPath',
            dartPath,
          ],
        ),
    );
  }

  final dart2js = await buildStep.fetchResource(dart2JsWorkerResource);
  final result = await dart2js.compile(args);
  final jsOutputId = dartEntrypointId.changeExtension(jsEntrypointExtension);
  final jsOutputFile = scratchSpace.fileFor(jsOutputId);
  if (result.succeeded && await jsOutputFile.exists()) {
    log.info(result.output);
    addNodePreamble(jsOutputFile);

    await scratchSpace.copyOutput(jsOutputId, buildStep);
    final jsSourceMapId =
        dartEntrypointId.changeExtension(jsEntrypointSourceMapExtension);
    await _copyIfExists(jsSourceMapId, scratchSpace, buildStep);
  } else {
    log.severe(result.output);
  }
}

Future<void> _copyIfExists(
    AssetId id, ScratchSpace scratchSpace, AssetWriter writer) async {
  final file = scratchSpace.fileFor(id);
  if (await file.exists()) {
    await scratchSpace.copyOutput(id, writer);
  }
}

void addNodePreamble(File output) {
  final preamble = getPreamble(minified: true);
  final contents = output.readAsStringSync();
  output
    ..writeAsStringSync(preamble)
    ..writeAsStringSync(contents, mode: FileMode.append);
}

/// Creates a `.packages` file unique to this entrypoint at the root of the
/// scratch space and returns it's filename.
///
/// Since multiple invocations of Dart2Js will share a scratch space and we only
/// know the set of packages involved the current entrypoint we can't construct
/// a `.packages` file that will work for all invocations of Dart2Js so a unique
/// file is created for every entrypoint that is run.
///
/// The filename is based off the MD5 hash of the asset path so that files are
/// unique regardless of situations like `web/foo/bar.dart` vs
/// `web/foo-bar.dart`.
Future<String> _createPackageFile(Iterable<AssetId> inputSources,
    BuildStep buildStep, ScratchSpace scratchSpace) async {
  final inputUri = buildStep.inputId.uri;
  final packageFileName =
      '.package-${md5.convert(inputUri.toString().codeUnits)}';
  final packagesFile =
      scratchSpace.fileFor(AssetId(buildStep.inputId.package, packageFileName));
  final packageNames = inputSources.map((s) => s.package).toSet();
  final packagesFileContent =
      packageNames.map((n) => '$n:packages/$n/').join('\n');
  await packagesFile
      .writeAsString('# Generated for $inputUri\n$packagesFileContent');
  return packageFileName;
}
