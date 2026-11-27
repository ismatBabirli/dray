package com.wainhq.wain.model

import android.content.Context
import com.wainhq.wain.wire.wireJson
import kotlinx.serialization.Serializable

/**
 * What the app ships under someone else's licence, and Wain's own, read from `licences.json`.
 * Apache-2.0, MIT and BSD all ask that their text reach whoever gets the app.
 */
@Serializable
data class Licences(val components: List<Component>, val licences: Map<String, String>) {
    /** [covers] holds the Maven groups it accounts for, which `LicencesTest` holds to build.gradle.kts. */
    @Serializable
    data class Component(val name: String, val licence: String, val copyright: String, val covers: List<String> = emptyList())

    companion object {
        private var loaded: Licences? = null

        fun parse(json: String): Licences = wireJson.decodeFromString(json)

        /** The bundled list, read from assets once. */
        fun load(context: Context): Licences =
            loaded ?: parse(context.assets.open("licences.json").bufferedReader().use { it.readText() }).also { loaded = it }
    }
}
