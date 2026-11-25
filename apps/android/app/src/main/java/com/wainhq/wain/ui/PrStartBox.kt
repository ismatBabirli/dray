package com.wainhq.wain.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.CallSplit
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.wainhq.wain.model.PullRequest
import com.wainhq.wain.model.PullRow
import com.wainhq.wain.model.prInitial
import com.wainhq.wain.model.prMachines
import com.wainhq.wain.model.prPrompt
import com.wainhq.wain.model.prRepoSlug
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.wire.SessionItem
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import java.util.UUID

// PullDetail.swift's `PrStartBox`: a task for the PR, the reader's own or a bot's, on the PR's own branch.

/**
 * A task for the PR on a new worktree of its own branch, the reader's or a bot's on the machine
 * the PR was read through. Always Auto: the page offers no stance.
 */
@Composable
fun PrStartBox(row: PullRow, pr: PullRequest, text: String, setText: (String) -> Unit, latest: SessionItem?, started: () -> Unit) {
    val store = LocalStore.current
    if (row.listing.isCrossRepository) {
        Text("Read only. This branch lives in a fork, so an agent here can't push to it.", style = Wain.Font.subhead.copy(color = Wain.secondary))
        return
    }
    val connected = store.live.filter { store.serverState[it.id] == ConnState.Connected }.map { it.id }
    val machines = prMachines(row, connected) { store.projects[it].orEmpty() }
    val initial = prInitial(row, machines)
    StartBox(
        prefsKey = "pr", text = text, setText = setText,
        placeholder = "What should the agent do with this pull request?",
        placeLabel = "Machine",
        machines = machines, initial = if (machines.isEmpty()) null else initial,
        clone = (if (row.key.startsWith("github:")) row.key.removePrefix("github:") else prRepoSlug(row.mark.url).orEmpty()) to row.repo,
        bots = store.bots[initial.server].orEmpty().map { initial.server to it },
        botCheckout = true,
        latest = latest,
        worktreeSwitch = false,
        note = {
            Row(Modifier.padding(horizontal = Wain.Space.xs), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.AutoMirrored.Filled.CallSplit, null, Modifier.size(14.dp), tint = Wain.secondary)
                Text(buildAnnotatedString {
                    append("New worktree on ")
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold, color = Wain.text)) { append(row.mark.headRefName) }
                    append(", the PR's own branch")
                }, style = Wain.Font.footnote.copy(color = Wain.secondary), maxLines = 2)
            }
        },
        run = { p ->
            val item = try {
                decodeOrNull<SessionItem>(store.call(p.server, "start_pr_session", jsonOf(
                    "sessionId" to UUID.randomUUID().toString().lowercase(),
                    "prompt" to prPrompt(pr, p.text),
                    "harness" to p.harness, "model" to p.model, "effort" to p.effort,
                    "permissionMode" to "auto", "fast" to p.fast, "cwd" to p.cwd,
                    "prHead" to mapOf("branch" to row.mark.headRefName, "repo" to row.repo),
                    "prNumber" to row.mark.number, "bot" to p.bot?.id,
                ), timeoutMs = 120_000))
            } catch (e: Exception) {
                // Asked before anything is made, so nothing is left to tidy up.
                if (e.message?.contains("unknown command") == true) throw IllegalStateException("This server is older than the pull requests page. Update it, then start the task again.")
                throw e
            }
            item?.let { store.created(p.server, it) }
        },
        started = { started() },
    )
}
