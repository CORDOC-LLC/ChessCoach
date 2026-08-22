package com.chesscoach.android.engine

import android.content.Context
import com.chesscoach.core.engine.EnginePool
import java.io.File

/**
 * Resolves the platform piece [EnginePool] needs and hands back a ready-to-use
 * instance: the Stockfish binary's path on real disk.
 *
 * No NNUE net asset is bundled or copied. Current Stockfish (unlike the older
 * dual "Big"/"Small" net architecture some docs still describe) embeds a
 * single default network directly into the binary via `incbin` at build time
 * -- confirmed by building this exact binary from a fresh `official-stockfish/
 * Stockfish` clone, whose `evaluate.h` only defines one `EvalFileDefaultName`
 * and whose `engine.cpp` only registers one `EvalFile` UCI option (no
 * `EvalFileSmall`). Overriding `EvalFile` at runtime would require shipping a
 * net file guaranteed to match this exact build's NNUE format version; simply
 * never touching the option and letting the binary use its own embedded net
 * is both simpler and safer against a version mismatch.
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

    /** Creates a fresh [EnginePool] wired to the bundled binary. Throws if
     *  [isEngineAvailable] is false -- callers must check first. */
    fun createEnginePool(): EnginePool {
        check(isEngineAvailable) { "Stockfish binary not bundled -- see android/README.md" }
        return EnginePool(binaryPath = binaryFile.absolutePath)
    }
}
