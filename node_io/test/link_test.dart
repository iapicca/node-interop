// Copyright (c) 2017, Anatoly Pulyaevskiy. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

@TestOn('node')
library link_test;

import 'package:node_io/node_io.dart';
import 'package:test/test.dart';

import 'fs_utils.dart';

void main() {
  group('Link', () {
    test('create', () async {
      final filepath = createFile('link_create_test.txt', 'data');
      final linkpath = createPath('link.txt');
      final link = Link(linkpath);
      final created = await link.create(filepath);
      expect(created.exists(), completion(isTrue));
    });

    test('createSync', () {
      final filepath = createFile('link_create_sync_test.txt', 'data');
      final linkpath = createPath('link_sync.txt');
      final link = Link(linkpath);
      link.createSync(filepath);
      expect(link.existsSync(), isTrue);
    });

    test('delete', () async {
      final filepath = createFile('link_delete_test.txt', 'data');
      final linkpath = createPath('link_delete.txt');
      final link = Link(linkpath);
      final created = await link.create(filepath);
      await created.delete();
      expect(created.exists(), completion(isFalse));
    });

    test('deleteSync', () {
      final filepath = createFile('link_delete_sync_test.txt', 'data');
      final linkpath = createPath('link_delete_sync.txt');
      final link = Link(linkpath);
      link.createSync(filepath);
      link.deleteSync();
      expect(link.existsSync(), isFalse);
    });

    test('rename', () async {
      final filepath = createFile('link_rename_test.txt', 'data');
      final linkpath = createPath('link_rename.txt');
      final link = Link(linkpath);
      final created = await link.create(filepath);
      final renamed = await created.rename(createPath('link_new_name.txt'));
      expect(renamed.exists(), completion(isTrue));
      expect(renamed.path, createPath('link_new_name.txt'));
    });

    test('renameSync', () {
      final filepath = createFile('link_rename_sync_test.txt', 'data');
      final linkpath = createPath('link_rename_sync.txt');
      final link = Link(linkpath);
      link.createSync(filepath);
      final renamed = link.renameSync(createPath('link_rename_sync_new.txt'));
      expect(renamed.existsSync(), isTrue);
      expect(renamed.path, createPath('link_rename_sync_new.txt'));
    });

    test('target and targetSync', () async {
      final filepath = createFile('link_target_test.txt', 'data');
      final linkpath = createPath('link_target.txt');
      final link = Link(linkpath);
      final created = await link.create(filepath);

      expect(created.target(), completion(filepath));
      expect(created.targetSync(), filepath);
    });

    test('update and updateSync', () async {
      final filepath = createFile('link_update_test.txt', 'data');
      final filepath2 = createFile('link_update_new_test.txt', 'data');
      final filepath3 = createFile('link_update_new_sync_test.txt', 'data');
      final linkpath = createPath('link_update.txt');
      final link = Link(linkpath);
      final created = await link.create(filepath);

      final updated = await created.update(filepath2);
      expect(updated.existsSync(), isTrue);
      expect(updated.targetSync(), filepath2);

      updated.updateSync(filepath3);
      expect(updated.existsSync(), isTrue);
      expect(updated.targetSync(), filepath3);
    });
  });
}
