package com.keel.manager.data

import android.content.Context
import android.net.Uri
import java.io.File
import java.io.FileOutputStream
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream
import org.json.JSONObject

/**
 * Backup / restore: one .keel zip containing data.json (everything, see
 * Repository.exportAll) plus every photo file under photos/<file name>.
 * Written through the Storage Access Framework (the caller supplies the
 * Uri), so no storage permission is needed. 200 MB hard limit, same as
 * the Flutter build.
 */
object BackupService {
    const val MAX_BACKUP_BYTES: Long = 200L * 1024L * 1024L
    const val DATA_FILE_NAME = "data.json"

    /** The photo file for a stored photoPath (a file name inside
     * filesDir/photos/). Never resolves outside that directory. */
    fun photoFile(context: Context, photoPath: String): File {
        val photosDir = File(context.filesDir, "photos")
        // photoPath is a file name only; strip any path the caller sneaks in.
        val name = File(photoPath).name
        return File(photosDir, name)
    }

    /** Copy [source] into filesDir/photos/ under a unique name. Returns the
     * stored file name, or null when the file is not a real image. */
    fun storePhoto(context: Context, source: File): String? {
        if (!PhotoValidation.isValidImage(source)) return null
        val photosDir = File(context.filesDir, "photos").apply { mkdirs() }
        val ext = when (PhotoValidation.imageFormat(source)) {
            "jpeg" -> "jpg"
            "png" -> "png"
            "webp" -> "webp"
            else -> return null
        }
        val name = "${newId()}.$ext"
        source.copyTo(File(photosDir, name))
        return name
    }

    /** Write the zip to [uri]. Returns the byte count written. */
    suspend fun exportTo(
        context: Context,
        repository: KeelRepository,
        uri: Uri,
    ): Long {
        val data = repository.exportAll().toString()
        val people = repository.run {
            // Collect photo file names referenced by people.
            val orgs = getOrganizations()
            val names = mutableSetOf<String>()
            for (org in orgs) {
                for (p in getPeople(org.id)) {
                    p.photoPath?.let { names.add(it) }
                }
            }
            names
        }
        var written = 0L
        context.contentResolver.openOutputStream(uri)?.use { raw ->
            ZipOutputStream(raw).use { zip ->
                zip.putNextEntry(ZipEntry(DATA_FILE_NAME))
                val bytes = data.toByteArray(Charsets.UTF_8)
                zip.write(bytes)
                zip.closeEntry()
                written += bytes.size
                for (name in people) {
                    val file = photoFile(context, name)
                    if (!file.exists()) continue
                    if (written + file.length() > MAX_BACKUP_BYTES) break
                    zip.putNextEntry(ZipEntry("photos/$name"))
                    file.inputStream().use { it.copyTo(zip) }
                    zip.closeEntry()
                    written += file.length()
                }
            }
        } ?: throw IllegalStateException("Could not open the backup destination.")
        return written
    }

    /** Read and validate a backup zip from [uri]. Returns the parsed data
     * JSON plus the photo bytes (name -> bytes) for the caller to restore.
     * Nothing is written to the database here — validation happens first. */
    fun readBackup(context: Context, uri: Uri): Pair<JSONObject, Map<String, ByteArray>> {
        var total = 0L
        var dataJson: JSONObject? = null
        val photos = mutableMapOf<String, ByteArray>()
        context.contentResolver.openInputStream(uri)?.use { raw ->
            ZipInputStream(raw).use { zip ->
                var entry = zip.nextEntry
                while (entry != null) {
                    if (!entry.isDirectory) {
                        val bytes = zip.readBytes()
                        total += bytes.size
                        if (total > MAX_BACKUP_BYTES) {
                            throw IllegalArgumentException("Backup is larger than 200 MB.")
                        }
                        when {
                            entry.name == DATA_FILE_NAME -> {
                                dataJson = JSONObject(String(bytes, Charsets.UTF_8))
                            }
                            entry.name.startsWith("photos/") -> {
                                val name = File(entry.name.removePrefix("photos/")).name
                                if (name.isNotEmpty()) photos[name] = bytes
                            }
                        }
                    }
                    zip.closeEntry()
                    entry = zip.nextEntry
                }
            }
        } ?: throw IllegalStateException("Could not open the backup file.")
        val data = dataJson ?: throw IllegalArgumentException("Backup has no data.json.")
        return data to photos
    }

    /** Write restored photo bytes into filesDir/photos/. */
    fun restorePhotos(context: Context, photos: Map<String, ByteArray>) {
        val photosDir = File(context.filesDir, "photos").apply { mkdirs() }
        for ((name, bytes) in photos) {
            val safe = File(name).name
            if (safe.isEmpty()) continue
            FileOutputStream(File(photosDir, safe)).use { it.write(bytes) }
        }
    }
}

/** Magic-byte validation for photos — never trust the file extension. */
object PhotoValidation {
    fun isValidImage(file: File): Boolean = imageFormat(file) != null

    /** "jpeg" | "png" | "webp" | null */
    fun imageFormat(file: File): String? {
        if (!file.exists() || file.length() < 12) return null
        val head = ByteArray(12)
        file.inputStream().use { it.read(head) }
        return when {
            head[0] == 0xFF.toByte() && head[1] == 0xD8.toByte() && head[2] == 0xFF.toByte() -> "jpeg"
            head[0] == 0x89.toByte() && head[1] == 0x50.toByte() && head[2] == 0x4E.toByte() && head[3] == 0x47.toByte() -> "png"
            head[0] == 0x52.toByte() && head[1] == 0x49.toByte() && head[2] == 0x46.toByte() && head[3] == 0x46.toByte()
                && head[8] == 0x57.toByte() && head[9] == 0x45.toByte() && head[10] == 0x42.toByte() && head[11] == 0x50.toByte() -> "webp"
            else -> null
        }
    }
}
