# Keel — R8 keep rules for release builds.
#
# The Flutter Gradle plugin already adds its own
# flutter_proguard_rules.pro (keeps the embedding + GeneratedPluginRegistrant).
# These rules cover the plugins that load classes by name at runtime, so
# shrinking cannot strip them. Drift/sqlite3 need none: they go through
# dart:ffi (native .so files are untouched by R8) and generated code.

# flutter_local_notifications: the plugin looks up its receiver/service
# classes by name when scheduling the daily digest.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# image_picker / file_picker / path_provider / shared_preferences /
# url_launcher: keep their plugin entry points (referenced from the
# generated registrant, but explicit is cheaper than a broken release).
-keep class io.flutter.plugins.** { *; }
