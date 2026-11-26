package com.wainhq.wain.wire

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/** One window of an agent's plan: `five_hour`, `weekly` or `other`, filled 0–100; Claude's older `rejected` line gives no figure. */
@Serializable
data class UsageWindow(
    val kind: String = "other",
    val usedPercent: Double? = null,
    /** RFC3339. */
    val resetsAt: String? = null,
    val minutes: Int? = null,
)

/**
 * The newest usage reading one agent reported on one server: `live_state.usage` and
 * `usage_changed`'s list. Everything but `harness` may be missing on a reading.
 */
@Serializable
data class UsageReading(
    val harness: String,
    val plan: String? = null,
    /** A window is spent. */
    val limited: Boolean = false,
    /** Claude's `overageStatus` as sent: `rejected` is extra usage off. */
    val overage: String? = null,
    val usingOverage: Boolean = false,
    /** RFC3339, when the server received it. */
    val at: String = "",
    val windows: List<UsageWindow> = emptyList(),
) {
    companion object {
        fun list(e: JsonElement?): List<UsageReading> = decodeList(e)
    }
}
