package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.Picks
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.NEW_SESSION
import com.wainhq.wain.store.shownBots
import com.wainhq.wain.voice.Dictation
import com.wainhq.wain.voice.Dictations
import com.wainhq.wain.voice.typesOnly
import kotlinx.coroutines.launch

/** The app's one new task, so its picks and its bot aim outlive the sheet. */
val LocalNewTask = compositionLocalOf<com.wainhq.wain.store.NewTask> { error("No NewTask provided") }

/**
 * New task, from the FAB or the rail: the prompt with its mic, then Run by (Me or a bot, the
 * aim-at-bot path), project, agent, machine and worktree, then Save draft and Start task. The
 * picks are `NewTask`'s, so they outlive the sheet; project, agent and machine open Run with.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewTaskSheet(started: (SessionKey) -> Unit, dismiss: () -> Unit) {
    val store = LocalStore.current
    val task = LocalNewTask.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var picking by remember { mutableStateOf(false) }
    var runBy by remember { mutableStateOf(false) }
    LaunchedEffect(task.server, task.harness) { task.load() }

    fun start() = scope.launch {
        val key = task.start() ?: return@launch
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        dismiss()
        started(key)
    }

    ModalBottomSheet(dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Wain.card,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)) {
        Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
            Text("New task", Modifier.padding(start = 24.dp, end = 24.dp, top = 4.dp, bottom = 16.dp), style = TitleStyle())
            Box(Modifier.padding(horizontal = 16.dp).releaseEndsHold(NEW_SESSION, store)) {
                if (Dictations.state(NEW_SESSION) != Dictation.Idle) DictationStrip(NEW_SESSION, task.text)
                else {
                    TextField(
                        task.text, { task.text = it }, Modifier.fillMaxWidth().heightIn(min = 168.dp),
                        label = { Text("Prompt") },
                        placeholder = { Text("What should it do?", color = Wain.tertiary) },
                        textStyle = Wain.Font.body.copy(lineHeight = 24.sp),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = Wain.raised, unfocusedContainerColor = Wain.raised,
                            focusedIndicatorColor = Wain.link, unfocusedIndicatorColor = Wain.secondary,
                            focusedLabelColor = Wain.link, unfocusedLabelColor = Wain.secondary, cursorColor = Wain.text,
                        ),
                    )
                    if (!store.typesOnly) Box(Modifier.align(Alignment.BottomEnd).padding(12.dp)) { MicButton(NEW_SESSION, 40.dp, Wain.tile) }
                }
            }
            Dictations.notes[NEW_SESSION]?.let { KeptNote(it, NEW_SESSION, Modifier.padding(start = 24.dp, end = 24.dp, top = 8.dp)) }
            Spacer(Modifier.height(12.dp))

            val bots = store.shownBots.filter { (s, _) -> store.serverState[s] == ConnState.Connected }
            Box {
                PickLine({ Glyph24 { botsGlyph(Wain.secondary, false, Wain.card) } }, "Run by", task.bot?.second?.name ?: "Me") { runBy = true }
                DropdownMenu(runBy, { runBy = false }, containerColor = Wain.raised) {
                    DropdownMenuItem({ Text("Me", style = Wain.Font.body) }, { task.runByMe(); runBy = false })
                    for ((server, bot) in bots) DropdownMenuItem(
                        { Text(bot.name, style = Wain.Font.body) }, { task.aim(bot, server); runBy = false },
                        leadingIcon = { BotFace(bot, 24.dp) },
                    )
                }
            }
            // A bot's task runs in its own folder, on its own machine, with no worktree.
            if (task.bot == null) PickLine({ Icon(Icons.Outlined.Folder, null, Modifier.size(22.dp), tint = Wain.secondary) }, "Project", task.project ?: "Pick one") { picking = true }
            PickLine({ AgentMark(task.harness, 20.dp, Wain.secondary) }, "Agent",
                listOfNotNull(task.model?.label ?: task.modelId.ifEmpty { Picks.agentLabels[task.harness] ?: task.harness }, task.effort?.let { Picks.effortLabels[it] ?: it }).joinToString(" · ")) { picking = true }
            if (task.bot == null) PickLine({ Icon(Icons.Outlined.Dns, null, Modifier.size(22.dp), tint = Wain.secondary) }, "Machine", task.server?.let { store.name(it) } ?: "None connected") { picking = true }
            if (task.bot == null) Row(Modifier.fillMaxWidth().height(64.dp).clickable { task.pickWorktree(!task.worktree) }.padding(start = 24.dp, end = 24.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Icon(Icons.Outlined.AccountTree, null, Modifier.size(22.dp), tint = Wain.secondary)
                Text("Worktree", Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp))
                PickSwitch(task.worktree) { task.pickWorktree(it) }
            }
            task.failure?.let { Text("Couldn't start. ${sentence(it)}", Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
            Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 16.dp, top = 24.dp), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                if (task.hasText) Text("Save draft", Modifier.clip(CircleShape).clickable(enabled = !task.sending) {
                    scope.launch { if (task.saveDraft()) dismiss() }
                }.padding(horizontal = 16.dp, vertical = 12.dp), style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium))
                Row(
                    Modifier.height(44.dp).clip(CircleShape).background(Wain.primary).alpha(if (task.ready) 1f else 0.4f)
                        .clickable(enabled = task.ready) { start() }.padding(horizontal = 24.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (task.sending) CircularProgressIndicator(Modifier.size(16.dp), color = Wain.onPrimary, strokeWidth = 2.dp)
                    else Text("Start task", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.onPrimary))
                }
            }
        }
    }
    if (picking) RunWithSheet(task) { picking = false }
}

@Composable
private fun PickLine(icon: @Composable () -> Unit, title: String, value: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).clickable(onClick = onClick).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { icon() }
        Column {
            Text(title, style = Wain.Font.body.copy(lineHeight = 22.sp))
            Text(value, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 18.sp, color = Wain.secondary), maxLines = 1)
        }
    }
}
