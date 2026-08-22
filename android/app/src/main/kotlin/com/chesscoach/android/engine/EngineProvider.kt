package com.chesscoach.android.engine

import android.content.Context
import com.chesscoach.core.engine.EnginePool
import java.io.File

/**
 * Resolves the platform pieces [EnginePool] needs and hands back a ready-to-use
 * instance: the Stockfish binary's path and the NNUE net's path on real disk
 * (UCI's `EvalFile` option needs a filesystem path -- it can't read an APK asset
 * directly, so the bundled net is copied to internal storage once).
 *
 * The binary itself is NOT bundled by this build (see android/README.md) --
 * [isEngineAvailable] is false until one is placed at
 * `app/src/main/jniLibs/<abi>/libstockfish.so` and the app is rebuilt. Every
 * screen that needs the engine must check this and degrade gracefully (as the
 * puzzle/opening/board-rules features, which need no engine, already do).
 */
class EngineProvider(private val context: Context) {

    /** The native library directory is the only app-writable-adjacent location
     *  Android (API 29+) permits executing a bundled binary from. */
    private val binaryFile: File
        get() = File(context.applicationInfo.nativeLibraryDir, "libstockfish.so")

    val isEngineAvailable: Boolean
        get() = binaryFile.exists() && binaryFile.canExecute()

    private var cachedNnuePath: String? = null

    private fun nnuePath(): String {
        cachedNnuePath?.let { return it }
        val dest = File(context.filesDir, "nn-37f18f62d772.nnue")
        if (!dest.exists() || dest.length() == 0L) {
            context.assets.open("nnue/nn-37f18f62d772.nnue").use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
        }
        cachedNnuePath = dest.absolutePath
        return dest.absolutePath
    }

    /** Creates a fresh [EnginePool] wired to the bundled binary/net. Throws if
     *  [isEngineAvailable] is false -- callers must check first. */
    fun createEnginePool(): EnginePool {
        check(isEngineAvailable) { "Stockfish binary not bundled -- see android/README.md" }
        return EnginePool(
            binaryPath = binaryFile.absolutePath,
            nnueSmallPath = nnuePath(),
        )
    }
}
