import 'dart:developer';

import 'package:boolean_selector/boolean_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meta/meta.dart';
import 'package:patrol/src/binding.dart';
import 'package:patrol/src/global_state.dart' as global_state;
import 'package:patrol/src/native/contracts/contracts.dart';
import 'package:patrol/src/native/native.dart';
import 'package:patrol_finders/patrol_finders.dart' as finders;
import 'package:patrol_log/patrol_log.dart';

/// We need [Group] to recreate test hierarchy.
// ignore: implementation_imports
import 'package:test_api/src/backend/group.dart';

/// We need [Test] to recreate test hierarchy.
// ignore: implementation_imports
import 'package:test_api/src/backend/test.dart';

import 'constants.dart' as constants;
import 'custom_finders/patrol_integration_tester.dart';

/// Signature for callback to [patrolTest].
typedef PatrolTesterCallback = Future<void> Function(PatrolIntegrationTester $);

/// A modification of [setUp] that works with Patrol's native automation.
void patrolSetUp(dynamic Function() body) {
  setUp(() async {
    if (constants.hotRestartEnabled) {
      await body();
      return;
    }

    final currentTest = global_state.currentTestFullName;

    final requestedToExecute = await PatrolBinding.instance.patrolAppService
        .waitForExecutionRequest(currentTest);

    if (requestedToExecute) {
      await body();
    }
  });
}

/// A modification of [tearDown] that works with Patrol's native automation.
void patrolTearDown(dynamic Function() body) {
  tearDown(() async {
    if (constants.hotRestartEnabled) {
      await body();
      return;
    }

    final currentTest = global_state.currentTestFullName;

    final requestedToExecute = await PatrolBinding.instance.patrolAppService
        .waitForExecutionRequest(currentTest);

    if (requestedToExecute) {
      await body();
    }
  });
}

/// Like [testWidgets], but with support for Patrol custom finders.
///
/// To customize the Patrol-specific configuration, set [config].
///
/// ### Using the default [WidgetTester]
///
/// If you need to do something using Flutter's [WidgetTester], you can access
/// it like this:
///
/// ```dart
/// patrolTest(
///    'increase counter text',
///    ($) async {
///      await $.tester.tap(find.byIcon(Icons.add));
///    },
/// );
/// ```
@isTest
void patrolTest(
  String description,
  PatrolTesterCallback callback, {
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
  finders.PatrolTesterConfig config = const finders.PatrolTesterConfig(
    printLogs: true,
  ),
  NativeAutomatorConfig nativeAutomatorConfig = const NativeAutomatorConfig(),
  LiveTestWidgetsFlutterBindingFramePolicy framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fadePointers,
}) {
  // DEBUG: Log handle count at patrolTest entry
  final handlesAtEntry =
      SemanticsBinding.instance.debugOutstandingSemanticsHandles;
  print(
    '[PATROL_DEBUG] patrolTest() entry: $handlesAtEntry handles (test: "$description")',
  );

  final patrolLog = PatrolLogWriter(config: {'printLogs': config.printLogs});
  final automator = NativeAutomator(config: nativeAutomatorConfig);
  final automator2 = NativeAutomator2(config: nativeAutomatorConfig);

  // DEBUG: Log handle count before ensureInitialized
  final handlesBeforeBinding =
      SemanticsBinding.instance.debugOutstandingSemanticsHandles;
  print(
    '[PATROL_DEBUG] Before PatrolBinding.ensureInitialized(): $handlesBeforeBinding handles',
  );

  final patrolBinding = PatrolBinding.ensureInitialized(nativeAutomatorConfig)
    ..framePolicy = framePolicy;

  // DEBUG: Log handle count after ensureInitialized
  final handlesAfterBinding =
      SemanticsBinding.instance.debugOutstandingSemanticsHandles;
  print(
    '[PATROL_DEBUG] After PatrolBinding.ensureInitialized(): $handlesAfterBinding handles',
  );
  if (handlesAfterBinding != handlesBeforeBinding) {
    print(
      '[PATROL_DEBUG] ⚠️ Handle count changed during PatrolBinding.ensureInitialized()!',
    );
    print(
      '[PATROL_DEBUG] Changed from $handlesBeforeBinding to $handlesAfterBinding',
    );
  }

  if (skip ?? false) {
    patrolLog.log(TestEntry(name: description, status: TestEntryStatus.skip));
  }

  // DEBUG: Log handle count before testWidgets() call
  final handlesBeforeTestWidgets =
      SemanticsBinding.instance.debugOutstandingSemanticsHandles;
  print(
    '[PATROL_DEBUG] Before testWidgets() call: $handlesBeforeTestWidgets handles',
  );

  testWidgets(
    description,
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
    (widgetTester) async {
      // DEBUG: Log handle count right after testWidgets callback starts
      final handlesAtCallbackStart =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] testWidgets callback start: $handlesAtCallbackStart handles',
      );

      widgetTester.binding.platformDispatcher.onSemanticsEnabledChanged = () {
        // This callback is empty on purpose. It's a workaround for tests
        // failing on iOS and (from Flutter 3.29.0) on Android.
        //
        // See https://github.com/leancodepl/patrol/issues/1474

        // DEBUG: Log handle count when semantics enabled changes
        final handlesOnChange =
            SemanticsBinding.instance.debugOutstandingSemanticsHandles;
        print(
          '[PATROL_DEBUG] onSemanticsEnabledChanged callback: $handlesOnChange handles',
        );
        print('[PATROL_DEBUG] Stack trace:\n${StackTrace.current}');
      };

      if (!constants.hotRestartEnabled) {
        // If Patrol's native automation feature is enabled, then this test will
        // be executed only if the native side requested it to be executed.
        // Otherwise, it returns early.

        final requestedToExecute = await patrolBinding.patrolAppService
            .waitForExecutionRequest(global_state.currentTestFullName);

        if (!requestedToExecute) {
          return;
        }
      }

      // DEBUG: Log handle count before automator.configure()
      final handlesBeforeConfigure =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] Before automator.configure(): $handlesBeforeConfigure handles',
      );

      await automator.configure();

      // DEBUG: Log handle count after automator.configure()
      final handlesAfterConfigure =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] After automator.configure(): $handlesAfterConfigure handles',
      );
      if (handlesAfterConfigure != handlesBeforeConfigure) {
        print(
          '[PATROL_DEBUG] ⚠️ Handle count changed during automator.configure()!',
        );
        print(
          '[PATROL_DEBUG] Changed from $handlesBeforeConfigure to $handlesAfterConfigure',
        );
        print('[PATROL_DEBUG] Stack trace:\n${StackTrace.current}');
      }
      // We don't have to call this line because automator.configure() does the same.
      // await automator2.configure();

      patrolLog.log(
        TestEntry(name: description, status: TestEntryStatus.start),
      );

      // DEBUG: Log handle count before PatrolIntegrationTester creation
      final handlesBeforeTester =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] Before PatrolIntegrationTester creation: $handlesBeforeTester handles',
      );

      final patrolTester = PatrolIntegrationTester(
        tester: widgetTester,
        nativeAutomator: automator,
        nativeAutomator2: automator2,
        config: config,
      );

      // DEBUG: Log handle count after PatrolIntegrationTester creation
      final handlesAfterTester =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] After PatrolIntegrationTester creation: $handlesAfterTester handles',
      );
      if (handlesAfterTester != handlesBeforeTester) {
        print(
          '[PATROL_DEBUG] ⚠️ Handle count changed during PatrolIntegrationTester creation!',
        );
        print(
          '[PATROL_DEBUG] Changed from $handlesBeforeTester to $handlesAfterTester',
        );
        print('[PATROL_DEBUG] Stack trace:\n${StackTrace.current}');
      }

      // DEBUG: Log handle count before test body execution
      final handlesBeforeTestBody =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] Before test body execution (callback): $handlesBeforeTestBody handles',
      );

      await callback(patrolTester);

      // DEBUG: Log handle count after test body execution
      final handlesAfterTestBody =
          SemanticsBinding.instance.debugOutstandingSemanticsHandles;
      print(
        '[PATROL_DEBUG] After test body execution (callback): $handlesAfterTestBody handles',
      );

      if (debugDefaultTargetPlatformOverride !=
          patrolBinding.workaroundDebugDefaultTargetPlatformOverride) {
        debugDefaultTargetPlatformOverride =
            patrolBinding.workaroundDebugDefaultTargetPlatformOverride;
      }

      if (constants.hotRestartEnabled &&
          global_state.isCurrentTestLastInGroup) {
        // Patrol log that test is finished
        // If test fails this code will not be executed
        patrolLog.log(
          LogEntry(
            message:
                'All tests were executed. Press "r" to start again or "q" to quit',
          ),
        );
        // Wait indefinitely in develop mode after the last test
        while (true) {
          await widgetTester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    },
  );
}

/// Creates a DartGroupEntry by visiting the subgroups of [parentGroup].
///
/// The initial [parentGroup] is the implicit, unnamed top-level [Group] present
/// in every test case.
@internal
DartGroupEntry createDartTestGroup(
  Group parentGroup, {
  String name = '',
  int level = 0,
  int maxTestCaseLength = global_state.maxTestLength,
  String? tags,
  String? excludeTags,
}) {
  final groupDTO = DartGroupEntry(
    name: name,
    type: GroupEntryType.group,
    entries: [],
    skip: parentGroup.metadata.skip,
    tags: parentGroup.metadata.tags.toList(),
  );

  for (final entry in parentGroup.entries) {
    // Trim names of current groups

    var name = entry.name;
    if (parentGroup.name.isNotEmpty) {
      // Assume that parentGroupName fits maxTestCaseLength
      // Assume that after cropping, test names are different.

      if (name.length > maxTestCaseLength) {
        name = name.substring(0, maxTestCaseLength);
      }

      name = deduplicateGroupEntryName(parentGroup.name, name);
    }

    switch (entry) {
      case Test _:
        if (entry.name == 'patrol_test_explorer') {
          // Ignore the bogus test that is used to discover the test structure.
          continue;
        }

        if (level < 1) {
          throw StateError('Test is not allowed to be defined at level $level');
        }

        if (tags != null) {
          final includeTagsSelector = BooleanSelector.parse(tags);

          // If the user provided tags, skip tests that don't match all of them.
          if (!includeTagsSelector.evaluate(entry.metadata.tags.contains)) {
            continue;
          }
        }

        if (excludeTags != null) {
          final excludeTagsSelector = BooleanSelector.parse(excludeTags);

          // Skip tests that do match any tags the user wants to exclude.
          if (excludeTagsSelector.evaluate(entry.metadata.tags.contains)) {
            continue;
          }
        }

        groupDTO.entries.add(
          DartGroupEntry(
            name: name,
            type: GroupEntryType.test,
            entries: [],
            skip: entry.metadata.skip,
            tags: entry.metadata.tags.toList(),
          ),
        );

      case Group _:
        groupDTO.entries.add(
          createDartTestGroup(
            entry,
            name: name,
            level: level + 1,
            maxTestCaseLength: maxTestCaseLength,
            tags: tags,
            excludeTags: excludeTags,
          ),
        );
    }
  }

  return groupDTO;
}

/// Allows for retrieving the name of a GroupEntry by stripping the names of all ancestor groups.
///
/// Example:
/// parentName = 'example_test myGroup'
/// currentName = 'example_test myGroup myTest'
/// should return 'myTest'
@internal
String deduplicateGroupEntryName(String parentName, String currentName) {
  return currentName.substring(parentName.length + 1, currentName.length);
}

/// Recursively prints the structure of the test suite and reports test count
/// of the top-most group
@internal
int reportGroupStructure(DartGroupEntry group, {int indentation = 0}) {
  var testCount = group.type == GroupEntryType.test ? 1 : 0;

  final indent = ' ' * indentation;
  final tag = group.type == GroupEntryType.group ? 'group' : 'test';
  debugPrint("$indent-- $tag: '${group.name}'");

  for (final entry in group.entries) {
    if (entry.type == GroupEntryType.test) {
      ++testCount;
      debugPrint("$indent     -- test: '${entry.name}'");
    } else {
      for (final subgroup in entry.entries) {
        testCount += reportGroupStructure(
          subgroup,
          indentation: indentation + 5,
        );
      }
    }
  }

  if (indentation == 0) {
    postEvent('testCount', {'testCount': testCount});
  }

  return testCount;
}
