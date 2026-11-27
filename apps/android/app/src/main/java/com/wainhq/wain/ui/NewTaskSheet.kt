package com.wainhq.wain.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.wainhq.wain.model.BranchList
import com.wainhq.wain.model.Picks
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.model.cloneOffers
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.NEW_SESSION
import com.wainhq.wain.store.NewTask
import com.wainhq.wain.store.shownBots
import com.wainhq.wain.voice.Dictation
import com.wainhq.wain.voice.Dictations
import com.wainhq.wain.voice.typesOnly
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.jsonOf
import kotlinx.coroutines.launch

/** The app's one new task, so its picks and its bot aim outlive the sheet. */
val LocalNewTask = compositionLocalOf<NewTask> { error("No NewTask provided") }

/** What the sheet shows: the picks, or one of the pages a pick swaps it to. */
private enum class TaskPage { Main, Project, Agent, Base, Clone, Attach, Models }

/**
 * New task, from the FAB or the rail (#35): the prompt and its mic, then Run by, Machine,
 * Project, Worktree (with Start from or Branch under it) and Agent, each asked once. Project and
 * Agent swap the sheet to a page of their own with a back arrow. A project another machine has
 * is picked to clone, and Start clones it onto this machine first. The picks are `NewTask`'s, so
 * they outlive the sheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NewTaskSheet(started: (SessionKey) -> Unit, dismiss: () -> Unit) {
    val store = LocalStore.current
    val task = LocalNewTask.current
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    var page by remember { mutableStateOf(TaskPage.Main) }
    var branches by remember { mutableStateOf<BranchList?>(null) }
    var branchError by remember { mutableStateOf<String?>(null) }
    val server = task.server
    val cwd = task.cwd
    LaunchedEffect(server, task.harness) { task.load() }
    // The checkout the branch row speaks for; read again whenever the place moves.
    LaunchedEffect(server, cwd, task.bot, task.clone) {
        branches = null
        branchError = null
        if (server != null && cwd != null && task.bot == null && task.clone == null) {
            branches = runCatching { decodeOrNull<BranchList>(store.call(server, "list_branches", jsonOf("cwd" to cwd))) }.getOrNull()
        }
    }

    fun start() {
        scope.launch {
            val key = task.start() ?: return@launch
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            dismiss()
            started(key)
        }
    }

    ModalBottomSheet(
        dismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), containerColor = Wain.card,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
        // A page takes Back for itself, to step out to the picks.
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = page == TaskPage.Main),
    ) {
        val back = { page = when (page) { TaskPage.Models -> TaskPage.Agent; TaskPage.Clone, TaskPage.Attach -> TaskPage.Project; else -> TaskPage.Main } }
        BackHandler(page != TaskPage.Main) { back() }
        when (page) {
            TaskPage.Main -> Picks(task, branches, branchError, { branches = it }, { branchError = it }, { page = it }, ::start, dismiss)
            TaskPage.Project -> ProjectPage(task, back) { page = it }
            TaskPage.Agent -> AgentPage(task, back) { page = TaskPage.Models }
            TaskPage.Base -> branches?.let { BasePage(task, it, back) } ?: LaunchedEffect(Unit) { page = TaskPage.Main }
            TaskPage.Models -> Pane { ModelLibrary(task.list, task.harness, back) }
            TaskPage.Clone, TaskPage.Attach -> server?.let { s ->
                Pane {
                    AttachProject(s, store.projects[s].orEmpty(), back, enterPath = page == TaskPage.Attach) { list ->
                        store.attached(s, list)
                        task.pickProject(list.maxByOrNull { it.lastSelected }?.name)
                        page = TaskPage.Main
                    }
                }
            } ?: LaunchedEffect(Unit) { page = TaskPage.Main }
        }
    }
}

/** The sheet's own frame for a page that brings its own title. */
@Composable
private fun Pane(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().padding(bottom = 8.dp)) { content() }
}

@Composable
private fun Picks(
    task: NewTask, branches: BranchList?, branchError: String?, setBranches: (BranchList) -> Unit, setError: (String?) -> Unit,
    open: (TaskPage) -> Unit, start: () -> Unit, dismiss: () -> Unit,
) {
    val store = LocalStore.current
    val scope = rememberCoroutineScope()
    var runBy by remember { mutableStateOf(false) }
    var machines by remember { mutableStateOf(false) }
    val server = task.server
    val machine = server?.let { store.name(it) }
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
                for ((s, bot) in bots) DropdownMenuItem(
                    { Text(bot.name, style = Wain.Font.body) }, { task.aim(bot, s); runBy = false },
                    leadingIcon = { BotFace(bot, 24.dp) },
                )
            }
        }
        // A bot's task runs on the bot's machine, in its folder, with no worktree.
        Box {
            PickLine({ VectorIcon(Icons.Outlined.Dns) }, "Machine", machine ?: "None connected", enabled = task.bot == null) { machines = true }
            DropdownMenu(machines, { machines = false }, containerColor = Wain.raised) {
                for (s in task.connected) DropdownMenuItem(
                    { Text(s.name, style = Wain.Font.body) }, { task.pickServer(s.id); machines = false },
                    trailingIcon = { if (s.id == server) Icon(Icons.Filled.Check, null, Modifier.size(18.dp), tint = Wain.text) },
                )
            }
        }
        if (task.bot == null) {
            val clone = task.clone
            PickLine({ VectorIcon(Icons.Outlined.Folder) }, "Project",
                clone?.let { "${it.name} · clones onto ${machine ?: "this machine"} first" } ?: task.project ?: "Pick one",
                enabled = server != null) { open(TaskPage.Project) }
            Row(Modifier.fillMaxWidth().height(56.dp).clickable { task.pickWorktree(!task.worktree) }.padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { VectorIcon(Icons.Outlined.AccountTree) }
                Text("Worktree", Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp))
                PickSwitch(task.worktree) { task.pickWorktree(it) }
            }
            if (clone == null && branches != null) BranchLine(task, branches, setBranches, setError) { open(TaskPage.Base) }
            branchError?.let { Text(sentence(it), Modifier.padding(start = 64.dp, end = 24.dp, bottom = 8.dp), style = Wain.Font.footnote.copy(color = Wain.destructive)) }
        }
        PickLine({ AgentMark(task.harness, 20.dp, Wain.secondary) }, "Agent",
            listOfNotNull(task.model?.label ?: task.modelId.ifEmpty { Picks.agentLabels[task.harness] ?: task.harness }, task.effort?.let { Picks.effortLabels[it] ?: it })
                .joinToString(" · ")) { open(TaskPage.Agent) }

        task.failure?.let {
            Text((if (task.clone != null) "Couldn't clone. " else "Couldn't start. ") + sentence(it),
                Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = Wain.Font.footnote.copy(color = Wain.destructive))
        }
        Row(Modifier.fillMaxWidth().padding(start = 24.dp, end = 16.dp, top = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            Spacer(Modifier.weight(1f))
            // A draft names a folder the machine holds, which a project still to clone is not.
            if (task.hasText && task.clone == null) Text("Save draft", Modifier.clip(CircleShape).clickable(enabled = !task.sending) {
                scope.launch { if (task.saveDraft()) dismiss() }
            }.padding(horizontal = 16.dp, vertical = 12.dp), style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium))
            Row(
                Modifier.height(44.dp).widthIn(max = 260.dp).clip(CircleShape).background(Wain.primary).alpha(if (task.ready) 1f else 0.4f)
                    .clickable(enabled = task.ready, onClick = start).padding(horizontal = 24.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                val ink = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.onPrimary)
                if (task.sending) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = Wain.onPrimary, strokeWidth = 2.dp)
                    // `clone_progress` while the clone runs: git's own lines, which say how far it is.
                    task.cloneLine?.takeIf { task.clone != null }?.let { Text(it, style = ink, maxLines = 1, overflow = TextOverflow.Ellipsis) }
                } else Text(if (task.clone != null) "Clone and start" else "Start task", style = ink)
            }
        }
    }
}

/**
 * Under Worktree: "Start from" when it is on and the repo offers a base, "Branch" when it is off.
 * A clean checkout switches branch at once; uncommitted files ask Bring or Stash, as the desktop does.
 */
@Composable
private fun BranchLine(task: NewTask, branches: BranchList, set: (BranchList) -> Unit, setError: (String?) -> Unit, pickBase: () -> Unit) {
    val store = LocalStore.current
    val scope = rememberCoroutineScope()
    var menu by remember { mutableStateOf(false) }
    var switching by remember { mutableStateOf<String?>(null) }
    val server = task.server ?: return
    val cwd = task.cwd ?: return

    fun checkout(branch: String, stash: Boolean) {
        scope.launch {
            setError(null)
            runCatching { decodeOrNull<BranchList>(store.call(server, "checkout_branch", jsonOf("cwd" to cwd, "branch" to branch, "stash" to stash))) }
                .onSuccess { it?.let(set) }
                // Git refusing names the files in the way, which is the part to act on.
                .onFailure { setError(it.message) }
        }
    }

    if (task.worktree) {
        if (branches.offersWorktreeBase) PickLine({}, "Start from", task.worktreeBase ?: branches.defaultBranch ?: branches.current.orEmpty(), onClick = pickBase)
        return
    }
    val current = branches.current ?: return
    Box {
        PickLine({}, "Branch", current) { menu = true }
        DropdownMenu(menu, { menu = false }, containerColor = Wain.raised) {
            for (b in branches.branches) DropdownMenuItem(
                { Text(b, style = Wain.Font.body, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                {
                    menu = false
                    if (b != current) scope.launch {
                        // Counted afresh: the agent or an editor may have written since the sheet opened.
                        val fresh = runCatching { decodeOrNull<BranchList>(store.call(server, "list_branches", jsonOf("cwd" to cwd))) }.getOrNull() ?: branches
                        set(fresh)
                        if (fresh.dirty > 0) switching = b else checkout(b, false)
                    }
                },
                trailingIcon = { if (b == current) Icon(Icons.Filled.Check, null, Modifier.size(18.dp), tint = Wain.text) },
            )
        }
    }
    switching?.let { b ->
        val n = branches.dirty
        AlertDialog(
            onDismissRequest = { switching = null },
            containerColor = Wain.card,
            title = { Text(if (n == 1) "1 uncommitted file" else "$n uncommitted files", style = Wain.Font.headline) },
            text = { Text("Switching to $b. Bring moves them with you; Stash keeps them here, saved for later.", style = Wain.Font.subhead.copy(color = Wain.secondary)) },
            confirmButton = { TextButton({ switching = null; checkout(b, false) }) { Text("Bring changes", color = Wain.text) } },
            dismissButton = { TextButton({ switching = null; checkout(b, true) }) { Text("Stash changes", color = Wain.text) } },
        )
    }
}

/** A page's head: the back arrow and its title. */
@Composable
private fun PageHead(title: String, back: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 24.dp, top = 4.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Wain.text) }
        Text(title, style = TitleStyle())
    }
}

@Composable
private fun PageColumn(content: @Composable ColumnScope.() -> Unit) =
    Column(Modifier.fillMaxWidth().imePadding().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(bottom = 24.dp), content = content)

@Composable
private fun Heading(text: String) = Text(text, Modifier.padding(horizontal = 24.dp, vertical = 8.dp),
    style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.secondary))

/** One radio row: the pick marked, its title and an optional line under it. */
@Composable
private fun RadioLine(picked: Boolean, title: String, detail: String? = null, pick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).selectable(picked, role = Role.RadioButton, onClick = pick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RadioButton(picked, null, Modifier.size(40.dp), colors = RadioButtonDefaults.colors(selectedColor = Wain.link, unselectedColor = Wain.secondary))
        Column {
            Text(title, style = Wain.Font.body.copy(lineHeight = 24.sp), maxLines = 1, overflow = TextOverflow.Ellipsis)
            detail?.let { Text(it, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary), maxLines = 1) }
        }
    }
}

/**
 * Project: the picked machine's projects; the other connected machines' that it lacks, by
 * GitHub repo, each picked to clone; then Clone from GitHub and Attach a folder.
 */
@Composable
private fun ProjectPage(task: NewTask, back: () -> Unit, open: (TaskPage) -> Unit) {
    val store = LocalStore.current
    val server = task.server
    val machine = server?.let { store.name(it) } ?: "this machine"
    PageColumn {
        PageHead("Project", back)
        Heading("On $machine")
        val choices = task.projectChoices
        if (choices.isEmpty()) Text("No projects on $machine yet.", Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = Wain.Font.body.copy(color = Wain.tertiary))
        for (c in choices) RadioLine(task.clone == null && c == task.projectChoice, c.label) { task.pick(c); back() }
        val offers = cloneOffers(
            server?.let { store.projects[it] }.orEmpty(),
            task.connected.filter { it.id != server }.map { s -> s.name to store.projects[s.id].orEmpty() },
        )
        if (offers.isNotEmpty()) {
            HorizontalDivider(Modifier.padding(vertical = 8.dp), color = Wain.hairline)
            Heading("On your other machines")
            for (o in offers) Row(
                Modifier.fillMaxWidth().height(64.dp).clickable { task.pickClone(o); back() }.padding(start = 24.dp, end = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                VectorIcon(Icons.Outlined.Folder)
                Column(Modifier.weight(1f)) {
                    Text(o.name, style = Wain.Font.body.copy(lineHeight = 24.sp), maxLines = 1)
                    Text("${o.slug} · on ${o.machine}", style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, color = Wain.secondary),
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (task.clone == o) Icon(Icons.Filled.Check, "Picked", Modifier.padding(horizontal = 12.dp).size(20.dp), tint = Wain.link)
                else Text("Clone", Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                    style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, color = Wain.link))
            }
            Text("Not on $machine yet. Picking one clones it into ~/wain before the task starts.",
                Modifier.padding(horizontal = 24.dp, vertical = 8.dp), style = Wain.Font.footnote.copy(fontSize = 12.sp, lineHeight = 16.sp, color = Wain.tertiary))
        }
        HorizontalDivider(Modifier.padding(vertical = 8.dp), color = Wain.hairline)
        ActionLine(Icons.Outlined.Download, "Clone from GitHub", server != null) { open(TaskPage.Clone) }
        ActionLine(Icons.Outlined.CreateNewFolder, "Attach a folder on $machine", server != null) { open(TaskPage.Attach) }
    }
}

@Composable
private fun ActionLine(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).alpha(if (enabled) 1f else 0.4f).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(icon, null, Modifier.size(22.dp), tint = Wain.text)
        Text(label, style = Wain.Font.body.copy(lineHeight = 24.sp))
    }
}

/** Agent: the machine's agents, the model, then effort, fast mode and permissions where they apply. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun AgentPage(task: NewTask, back: () -> Unit, more: () -> Unit) {
    val store = LocalStore.current
    val machine = task.server?.let { store.name(it) } ?: "this machine"
    val model = task.model
    PageColumn {
        PageHead("Agent", back)
        val agents = task.available.filter { it.available }
        if (agents.isNotEmpty()) {
            Heading("Agents on $machine")
            FlowRow(Modifier.padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                for (a in agents) FilterPill(a.label, a.harness == task.harness) { task.pickHarness(a.harness) }
            }
            Spacer(Modifier.height(8.dp))
        }
        Heading("Model")
        FlowRow(Modifier.padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for ((id, label) in shortlisted(task.list, task.harness, task.modelId)) FilterPill(label, id == task.modelId) { task.pickModel(id) }
            if (task.list.isNotEmpty()) FilterPill("More models", false, onClick = more)
        }
        HorizontalDivider(Modifier.padding(top = 16.dp, bottom = 8.dp), color = Wain.hairline)
        if (model != null && model.efforts.isNotEmpty()) {
            MenuLine("Effort", task.effort?.let { Picks.effortLabels[it] ?: it }.orEmpty(), model.efforts.map { it to (Picks.effortLabels[it] ?: it) },
                task.effort, task::pickEffort)
        }
        if (Picks.offersFast(task.harness, model)) Row(Modifier.fillMaxWidth().height(56.dp).clickable { task.pickFast(!task.fast) }.padding(horizontal = 24.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text("Fast mode", Modifier.weight(1f), style = Wain.Font.body.copy(lineHeight = 24.sp))
            PickSwitch(task.fast) { task.pickFast(it) }
        }
        if (Picks.offersStances(task.harness)) {
            MenuLine("Permissions", task.stanceLabel, Picks.stances.filter { Picks.honours(task.harness, it.first) },
                Picks.stanceFor(task.harness, task.stance), task::pickStance)
        }
    }
}

/** A row whose value comes from a menu: its title over the value, and the menu's mark. */
@Composable
private fun <T> MenuLine(title: String, value: String, choices: List<Pair<T, String>>, selected: T?, pick: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().height(64.dp).clickable { open = true }.padding(horizontal = 24.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(title, style = Wain.Font.body.copy(lineHeight = 22.sp))
                Text(value, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 18.sp, color = Wain.secondary), maxLines = 1)
            }
            Icon(Icons.Filled.ExpandMore, null, Modifier.size(22.dp), tint = Wain.secondary)
        }
        Box(Modifier.align(Alignment.BottomEnd).padding(end = 24.dp)) {
            DropdownMenu(open, { open = false }, containerColor = Wain.raised) {
                for ((v, label) in choices) DropdownMenuItem(
                    { Text(label, style = Wain.Font.body) }, { open = false; pick(v) },
                    trailingIcon = { if (v == selected) Icon(Icons.Filled.Check, null, Modifier.size(18.dp), tint = Wain.text) },
                )
            }
        }
    }
}

/** Start from: the default branch, fetched fresh, then local and remote-only branches, narrowed by a filter. */
@Composable
private fun BasePage(task: NewTask, branches: BranchList, back: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val (default, local, remote) = branches.worktreeOptions(query)
    PageColumn {
        PageHead("Start from", back)
        Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { SearchField(query, "Filter branches") { query = it } }
        default?.let { RadioLine(task.worktreeBase == null, it, "Default branch, fetched fresh") { task.worktreeBase = null; back() } }
        for (b in local) RadioLine(task.worktreeBase == b, b) { task.worktreeBase = b; back() }
        if (remote.isNotEmpty()) {
            Heading("On the remote")
            for (b in remote) RadioLine(task.worktreeBase == b, b) { task.worktreeBase = b; back() }
        }
        if (default == null && local.isEmpty() && remote.isEmpty()) Text("No branch matches.", Modifier.padding(24.dp), style = Wain.Font.body.copy(color = Wain.tertiary))
    }
}

@Composable
private fun VectorIcon(icon: ImageVector) = Icon(icon, null, Modifier.size(22.dp), tint = Wain.secondary)

@Composable
private fun PickLine(icon: @Composable () -> Unit, title: String, value: String, enabled: Boolean = true, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().height(56.dp).clickable(enabled = enabled, onClick = onClick).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { icon() }
        Column {
            Text(title, style = Wain.Font.body.copy(lineHeight = 22.sp))
            Text(value, style = Wain.Font.footnote.copy(fontSize = 14.sp, lineHeight = 18.sp, color = Wain.secondary), maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}
