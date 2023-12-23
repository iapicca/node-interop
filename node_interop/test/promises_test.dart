// Copyright (c) 2017, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

@JS()
@TestOn('node')
library promises_test;

import 'dart:async';

import 'package:js/js.dart';
import 'package:node_interop/node.dart';
import 'package:node_interop/test.dart';
import 'package:node_interop/util.dart';
import 'package:test/test.dart';

const promisesJS = '''
exports.createPromise = function (value) {
    final promise = new Promise((resolve, reject) => {
        setTimeout(() => {
            resolve(value);
        });
    });
    return promise;
};
exports.receivePromise = function (promise) {
    return promise.then((value) => {
        return value.repeat(3);
    }, (error) => {
        throw error.repeat(3);
    });
}
''';

@JS()
@anonymous
abstract class JsPromises {
  external Promise createPromise(value);
  external Promise receivePromise(promise);
}

void main() {
  final promises = createFile('promises.js', promisesJS);

  test('promiseToFuture', () async {
    final JsPromises js = require(promises);
    final promise = js.createPromise('Futures are better than Promises');
    final future = promiseToFuture(promise);
    expect(future, completion('Futures are better than Promises'));
  });

  test('futureToPromise', () {
    final JsPromises js = require(promises);
    final future = Future.value('Yes');
    final promise = futureToPromise(future);
    final promise2 = js.receivePromise(promise);
    expect(promiseToFuture(promise2), completion('YesYesYes'));
  });

  test('create promise in Dart', () {
    final JsPromises js = require(promises);
    final promise = Promise(allowInterop((resolve, reject) {
      resolve('Yas');
    }));
    final promise2 = js.receivePromise(promise);
    expect(promiseToFuture(promise2), completion('YasYasYas'));
  });

  test('reject a Promise', () {
    final promise = Promise(allowInterop((resolve, reject) {
      reject('No');
    }));
    expect(promiseToFuture(promise), throwsA('No'));
  });

  test('reject a Future', () {
    final JsPromises js = require(promises);
    final future = Future.error('No');
    final promise = futureToPromise(future);
    final promise2 = js.receivePromise(promise);
    expect(promiseToFuture(promise2), throwsA('NoNoNo'));
  });
}
