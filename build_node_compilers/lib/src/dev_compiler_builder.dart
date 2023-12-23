// Copyright (c) 2018, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bazel_worker/bazel_worker.dart';
import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
import 'package:path/path.dart' as path;
import 'package:scratch_space/scratch_space.dart';

import '../builders.dart';
import 'common.dart';
import 'errors.dart';

const jsModuleErrorsExtension = '.ddc_node.js.errors';
const jsModuleExtension = '.ddc_node.js';
const jsSourceMapExtension = '.ddc_node.js.map';

const _defaultSdkKernelPath = 'lib/_internal/ddc_sdk.dill';

/// A builder which can output ddc modules!
class DevCompilerBuilder implements Builder {
  final bool useIncrementalCompiler;

  final DartPlatform platform;

  /// The sdk kernel file for the current platform.
  final String sdkKernelPath;

  /// The root directory of the platform's dart SDK.
  ///
  /// If not provided, defaults to the directory of
  /// [Platform.resolvedExecutable].
  ///
  /// On flutter this is the path to the root of the flutter_patched_sdk
  /// directory, which contains the platform kernel files.
  final String platformSdk;

  /// The absolute path to the libraries file for the current platform.
  ///
  /// If not provided, defaults to "lib/libraries.json" in the sdk directory.
  final String librariesPath;

  DevCompilerBuilder({
    bool useIncrementalCompiler = true,
    required this.platform,
    this.sdkKernelPath = _defaultSdkKernelPath,
    String? librariesPath,
    String? platformSdk,
  })  : useIncrementalCompiler = useIncrementalCompiler,
        platformSdk = platformSdk ?? sdkDir,
        librariesPath = librariesPath ??
            path.join(
              platformSdk ?? sdkDir,
              'lib',
              'libraries.json',
            ),
        buildExtensions = {
          moduleExtension(platform): [
            jsModuleExtension,
            jsModuleErrorsExtension,
            jsSourceMapExtension
          ],
        };

  @override
  final Map<String, List<String>> buildExtensions;

  @override
  Future build(BuildStep buildStep) async {
    final module = Module.fromJson(
        json.decode(await buildStep.readAsString(buildStep.inputId))
            as Map<String, Object?>);
    // Entrypoints always have a `.module` file for ease of looking them up,
    // but they might not be the primary source.
    if (module.primarySource.changeExtension(moduleExtension(platform)) !=
        buildStep.inputId) {
      return;
    }

    Future<void> handleError(e) async {
      await buildStep.writeAsString(
          module.primarySource.changeExtension(jsModuleErrorsExtension), '$e');
      log.severe('$e');
    }

    try {
      await _createDevCompilerModule(
        module,
        buildStep,
        useIncrementalCompiler,
        platformSdk,
        librariesPath,
        sdkKernelPath: sdkKernelPath,
      );
    } on DartDevcCompilationException catch (e) {
      await handleError(e);
    } on MissingModulesException catch (e) {
      await handleError(e);
    }
  }
}

/// Compile [module] with the dev compiler.
Future<void> _createDevCompilerModule(
  Module module,
  BuildStep buildStep,
  bool useIncrementalCompiler,
  String dartSdk,
  String librariesPath, {
  String sdkKernelPath = _defaultSdkKernelPath,
  bool debugMode = true,
}) async {
  final transitiveDeps = await buildStep.trackStage('CollectTransitiveDeps',
      () => module.computeTransitiveDependencies(buildStep));
  final transitiveKernelDeps = [
    for (final dep in transitiveDeps)
      dep.primarySource.changeExtension(ddcKernelExtension)
  ];
  final scratchSpace = await buildStep.fetchResource(scratchSpaceResource);

  final allAssetIds = <AssetId>{...module.sources, ...transitiveKernelDeps};
  await buildStep.trackStage(
    'EnsureAssets',
    () => scratchSpace.ensureAssets(allAssetIds, buildStep),
  );
  final jsId = module.primarySource.changeExtension(jsModuleExtension);
  final jsOutputFile = scratchSpace.fileFor(jsId);
  final sdkSummary = path.url.join(dartSdk, sdkKernelPath);

  final packagesFile = await createPackagesFile(allAssetIds);
  final request = WorkRequest()
    ..arguments.addAll([
      '--dart-sdk-summary=$sdkSummary',
      '--modules=common',
      '--no-summarize',
      '-o',
      jsOutputFile.path,
      debugMode ? '--source-map' : '--no-source-map',
      for (final dep in transitiveDeps) _summaryArg(dep),
      '--packages=${packagesFile.absolute.uri}',
      '--module-name=${ddcModuleName(jsId)}',
      '--multi-root-scheme=$multiRootScheme',
      '--multi-root=.',
      '--track-widget-creation',
      '--inline-source-map',
      '--libraries-file=${path.toUri(librariesPath)}',
      if (useIncrementalCompiler) ...[
        '--reuse-compiler-result',
        '--use-incremental-compiler',
      ],
      for (final source in module.sources) _sourceArg(source),
    ])
    ..inputs.add(Input()
      ..path = sdkSummary
      ..digest = [0])
    ..inputs.addAll(
        await Future.wait(transitiveKernelDeps.map((dep) async => Input()
          ..path = scratchSpace.fileFor(dep).path
          ..digest = (await buildStep.digest(dep)).bytes)));

  WorkResponse response;
  try {
    final driverResource = dartdevkDriverResource;
    final driver = await buildStep.fetchResource(driverResource);
    response = await driver.doWork(request,
        trackWork: (response) =>
            buildStep.trackStage('Compile', () => response, isExternal: true));
  } finally {
    await packagesFile.parent.delete(recursive: true);
  }

  // TODO(jakemac53): Fix the ddc worker mode so it always sends back a bad
  // status code if something failed. Today we just make sure there is an output
  // JS file to verify it was successful.
  final message = response.output
      .replaceAll('${scratchSpace.tempDir.path}/', '')
      .replaceAll('$multiRootScheme:///', '');
  if (response.exitCode != EXIT_CODE_OK ||
      !jsOutputFile.existsSync() ||
      message.contains('Error:')) {
    throw DartDevcCompilationException(jsId, message);
  } else {
    if (message.isNotEmpty) {
      log.info('\n$message');
    }
    // Copy the output back using the buildStep.
    await scratchSpace.copyOutput(jsId, buildStep);
    if (debugMode) {
      // We need to modify the sources in the sourcemap to remove the custom
      // `multiRootScheme` that we use.
      final sourceMapId =
          module.primarySource.changeExtension(jsSourceMapExtension);
      final file = scratchSpace.fileFor(sourceMapId);
      final content = await file.readAsString();
      final json = jsonDecode(content);
      json['sources'] = fixSourceMapSources((json['sources'] as List).cast());
      await buildStep.writeAsString(sourceMapId, jsonEncode(json));
    }
  }
}

/// Returns the `--summary=` argument for a dependency.
String _summaryArg(Module module) {
  final kernelAsset = module.primarySource.changeExtension(ddcKernelExtension);
  final moduleName =
      ddcModuleName(module.primarySource.changeExtension(jsModuleExtension));
  return '--summary=${scratchSpace.fileFor(kernelAsset).path}=$moduleName';
}

/// The url to compile for a source.
///
/// Use the package: path for files under lib and the full absolute path for
/// other files.
String _sourceArg(AssetId id) {
  final uri = canonicalUriFor(id);
  return uri.startsWith('package:') ? uri : '$multiRootScheme:///${id.path}';
}

/// Copied to `web/stack_trace_mapper.dart`, these need to be kept in sync.
///
/// Given a list of [uris] as [String]s from a sourcemap, fixes them up so that
/// they make sense in a browser context.
///
/// - Strips the scheme from the uri
/// - Strips the top level directory if its not `packages`
List<String> fixSourceMapSources(List<String> uris) {
  return uris.map((source) {
    final uri = Uri.parse(source);
    // We only want to rewrite multi-root scheme uris.
    if (uri.scheme.isEmpty) return source;
    final newSegments = uri.pathSegments.first == 'packages'
        ? uri.pathSegments
        : uri.pathSegments.skip(1);
    return Uri(path: path.url.joinAll(['/'].followedBy(newSegments)))
        .toString();
  }).toList();
}

/// The module name according to ddc for [jsId] which represents the real js
/// module file.
String ddcModuleName(AssetId jsId) {
  final jsPath = jsId.path.startsWith('lib/')
      ? jsId.path.replaceFirst('lib/', 'packages/${jsId.package}/')
      : jsId.path;
  return jsPath.substring(0, jsPath.length - jsModuleExtension.length);
}
