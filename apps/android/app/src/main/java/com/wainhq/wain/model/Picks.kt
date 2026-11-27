package com.wainhq.wain.model

import com.wainhq.wain.wire.Project

import kotlinx.serialization.Serializable

@Serializable
data class Model(
    val id: String,
    val label: String = id,
    val efforts: List<String> = emptyList(),
    val defaultEffort: String? = null,
    val supportsFast: Boolean = false,
    /** Off the shortlist by default: a pinned older generation, reachable but not offered. */
    val secondary: Boolean? = null,
)

@Serializable
data class AgentAvailability(val harness: String, val available: Boolean = false, val label: String = harness, val reason: String = "")

@Serializable
data class BranchList(
    val current: String? = null,
    val branches: List<String> = emptyList(),
    /** On a remote with no local copy; absent from an older server's list. */
    val remoteBranches: List<String> = emptyList(),
    val defaultBase: String? = null,
    val dirty: Int = 0,
) {
    /** `origin/main` as the branch it names. */
    val defaultBranch: String? get() = defaultBase?.substringAfter('/')

    /** A repo with no remote and one branch has nothing to start a worktree from. Picks.swift's. */
    val offersWorktreeBase: Boolean get() = defaultBase != null || branches.size + remoteBranches.size > 1

    /** "Start from"'s choices for a filter: the default branch apart, then local, then remote-only, names starting with it first. */
    fun worktreeOptions(query: String): Triple<String?, List<String>, List<String>> {
        val q = query.trim().lowercase()
        fun keep(b: String) = q.isEmpty() || q in b.lowercase()
        fun rank(names: List<String>) = names.filter { it != defaultBranch && keep(it) }.sortedBy { !it.lowercase().startsWith(q) }
        return Triple(defaultBranch?.takeIf { keep(it) }, rank(branches), rank(remoteBranches))
    }
}

/**
 * A project another connected machine holds and the picked one lacks: its GitHub slug, the
 * folder it clones to, and where it was seen. `remote` is the server's key for it.
 */
data class CloneOffer(val slug: String, val name: String, val machine: String, val remote: String = "github.com/$slug")

/** `Project.remote` is git's origin as `host/owner/repo`, lowercased: only a GitHub one has a slug `gh` can clone. */
fun githubSlug(remote: String?): String? = remote?.removePrefix("github.com/")?.takeIf { it != remote && it.count { c -> c == '/' } == 1 }

/**
 * New task's "On your other machines": every other machine's GitHub projects whose `remote` no
 * project `here` has, one per repo, in the machines' order. A project with no GitHub remote is never offered.
 */
fun cloneOffers(here: List<Project>, others: List<Pair<String, List<Project>>>): List<CloneOffer> {
    val held = here.mapNotNull { it.remote?.lowercase() }.toMutableSet()
    return others.flatMap { (machine, projects) ->
        projects.mapNotNull { p ->
            val remote = p.remote?.lowercase() ?: return@mapNotNull null
            val slug = githubSlug(remote) ?: return@mapNotNull null
            if (!held.add(remote)) null else CloneOffer(slug, slug.substringAfterLast('/'), machine, remote)
        }
    }
}


@Serializable
data class GithubRepo(val slug: String, val description: String? = null, val path: String? = null)

@Serializable
data class CloneProgress(val slug: String, val line: String = "")

/**
 * The desktop composer's rules, restated since neither side can call the other: `permission.ts`,
 * `fastMode.ts`, `model.ts` and `liveControls.ts`, as the iOS app's `Picks` restates them too.
 * Change one there, change it here.
 */
object Picks {
    /** `DEFAULT_MODEL_FOR`. Empty is "let the harness decide". */
    val defaultModel = mapOf("claude_code" to "opus", "codex" to "gpt-6.2-sol", "pi" to "", "fx" to "", "grok" to "grok-4.7")
    const val DEFAULT_EFFORT = "high"
    val agentLabels = mapOf("claude_code" to "Claude Code", "codex" to "Codex", "pi" to "pi", "fx" to "fx", "grok" to "Grok")
    val effortLabels = mapOf("low" to "Low", "medium" to "Medium", "high" to "High", "xhigh" to "Extra High", "max" to "Max", "ultra" to "Ultra")
    val stances = listOf("bypassPermissions" to "Bypass permissions", "manual" to "Ask every time", "plan" to "Plan", "auto" to "Auto")

    /** `HONOURED`: absent means every stance applies. */
    private val honoured = mapOf(
        "codex" to listOf("bypassPermissions", "manual", "auto"),
        "pi" to emptyList(),
        "fx" to listOf("manual", "auto", "bypassPermissions"),
        "grok" to listOf("manual", "auto", "bypassPermissions"),
    )

    fun honours(harness: String, mode: String) = honoured[harness]?.contains(mode) ?: true

    /** One honoured stance is not a menu, and pi honours none. */
    fun offersStances(harness: String) = stances.count { honours(harness, it.first) } > 1

    /** `stanceFor`: what the session will actually run, which is what the index records. */
    fun stanceFor(harness: String, mode: String): String {
        if (honours(harness, mode)) return mode
        return when (harness) {
            "fx", "codex" -> if (mode == "plan") "manual" else "auto"
            "grok" -> if (mode == "plan") "manual" else "bypassPermissions"
            else -> "bypassPermissions"
        }
    }

    /**
     * `taskStance`: [stanceFor] for a task that already exists. A pi task recorded `plan` keeps it,
     * since it got there by moving from a `plan` task and must not come out able to write.
     */
    fun taskStance(harness: String, mode: String) = if (harness == "pi" && mode == "plan") "plan" else stanceFor(harness, mode)

    /** What each harness carries onto a prompt sent while a turn runs; `send_msg`'s gate states it too. */
    private val live = mapOf(
        "claude_code" to setOf("model", "stance", "fast"), "grok" to setOf("model", "effort", "fast"),
        "pi" to setOf("model", "effort"), "fx" to setOf("model", "effort", "stance", "fast"), "codex" to emptySet(),
    )

    fun lockedMidTurn(harness: String, control: String, busy: Boolean) = busy && live[harness]?.contains(control) != true

    /** The harness needs a route to fast mode (pi has none) and the model a faster tier; fx decides per model itself. */
    fun offersFast(harness: String, model: Model?): Boolean {
        if (harness !in setOf("claude_code", "codex", "fx", "grok")) return false
        return model?.supportsFast ?: (harness == "fx")
    }

    /** `usableModel`: a pick this list cannot run falls to the harness's default, never to the head of the list. */
    fun usableModel(models: List<Model>, picked: String, harness: String): String {
        if (models.isEmpty() || models.any { it.id == picked }) return picked
        val fallback = defaultModel[harness].orEmpty()
        if (fallback.isEmpty()) return ""
        return if (models.any { it.id == fallback }) fallback else models[0].id
    }

    /** `usableEffort`: the pick, else the model's default, else the app's, else the top rung. */
    fun usableEffort(model: Model, remembered: String?): String? {
        if (model.efforts.isEmpty()) return null
        for (wanted in listOf(remembered, model.defaultEffort, DEFAULT_EFFORT)) if (wanted != null && wanted in model.efforts) return wanted
        return model.efforts.last()
    }
}
