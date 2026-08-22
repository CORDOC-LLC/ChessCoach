package com.chesscoach.core.engine

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.launch
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter

/** Line-based transport to a UCI engine process. Abstracted so [EnginePool] doesn't
 *  depend on `Process` directly and can be driven by a fake in tests. */
interface UciTransport {
    /** Engine responses, one line at a time, in order. */
    val lines: Channel<String>

    fun send(command: String)
    fun close()
}

/** Spawns [binaryPath] as a child process and speaks UCI over its stdin/stdout.
 *
 * On Android, `binaryPath` must point at a file inside the app's
 * `nativeLibraryDir` (e.g. `.../lib/arm64-v8a/libstockfish.so`) -- that is the only
 * app-writable-adjacent location the OS permits executing from on API 29+. See
 * `android/README.md` for how that binary gets there.
 */
class ProcessUciTransport(binaryPath: String, scope: CoroutineScope) : UciTransport {
    override val lines: Channel<String> = Channel(Channel.UNLIMITED)

    private val process = ProcessBuilder(binaryPath)
        .redirectErrorStream(true)
        .start()
    private val writer = OutputStreamWriter(process.outputStream)

    init {
        scope.launch(Dispatchers.IO) {
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            while (true) {
                val line = reader.readLine() ?: break
                lines.trySend(line)
            }
            lines.close()
        }
    }

    override fun send(command: String) {
        writer.write(command)
        writer.write("\n")
        writer.flush()
    }

    override fun close() {
        try { send("quit") } catch (_: Exception) {}
        process.destroy()
        lines.close()
    }
}
