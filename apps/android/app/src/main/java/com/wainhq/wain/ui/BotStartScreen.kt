package com.wainhq.wain.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.unit.dp
import com.wainhq.wain.model.Model
import com.wainhq.wain.model.Picks
import com.wainhq.wain.model.SessionKey
import com.wainhq.wain.net.ConnState
import com.wainhq.wain.store.botChat
import com.wainhq.wain.wire.Bot
import com.wainhq.wain.wire.SessionItem
import com.wainhq.wain.wire.decodeOrNull
import com.wainhq.wain.wire.get
import com.wainhq.wain.wire.jsonOf
import com.wainhq.wain.wire.sentFrom
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * A bot before its first message: its greeting, and a field aimed at its folder. The send starts
 * the chat, which `started` opens in its place. iOS's `BotStartView`, over the same composer.
 */
/** A bot with no chat yet keeps its first message here, like a reply's draft. */
fun botStartDraft(server: String, botId: String) = SessionKey(server, "bot-start-$botId")

@Composable
fun BotStartScreen(server: String, bot: Bot, back: () -> Unit, started: (SessionKey) -> Unit) {
    val store = LocalStore.current
    val scope = rememberCoroutineScope()
    // Its words live in the drafts like a reply's, so dictation lands in them the same way.
    val draft = botStartDraft(server, bot.id)
    val text = store.drafts[draft].orEmpty()
    var sending by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf<String?>(null) }
    var editing by remember { mutableStateOf(false) }
    val connected = store.serverState[server] == ConnState.Connected

    // A chat that opened meanwhile (another client wrote first) takes this page's place.
    val chat = store.botChat(server, bot).lastOrNull()
    LaunchedEffect(chat) { chat?.let(started) }

    fun send() {
        val words = text.trim()
        if (words.isEmpty() || sending || !connected) return
        sending = true
        failed = null
        scope.launch {
            try {
                // Claude Code where the machine has it, else the first agent it can run, as the new-task picks fall back.
                val agents = runCatching {
                    com.wainhq.wain.wire.decodeList<com.wainhq.wain.model.AgentAvailability>(store.call(server, "agent_availability"))
                }.getOrDefault(emptyList()).filter { it.available }
                val harness = agents.firstOrNull { it.harness == "claude_code" }?.harness ?: agents.firstOrNull()?.harness ?: "claude_code"
                val models = store.models(server, harness)
                val model = Picks.defaultModel[harness].orEmpty().let { want -> models.firstOrNull { it.id == want } ?: models.firstOrNull() }
                val id = UUID.randomUUID().toString()
                val reply = store.call(server, "send_msg", jsonOf(
                    "sessionId" to id, "prompt" to words, "attachmentPaths" to emptyList<String>(),
                    "harness" to harness, "model" to (model?.id ?: ""), "effort" to model?.let { m: Model -> Picks.usableEffort(m, null) },
                    "permissionMode" to Picks.stanceFor(harness, "auto"), "fast" to false, "cwd" to bot.path,
                    "branch" to null, "useWorktree" to false, "worktreeName" to null, "baseRef" to null, "isNewSession" to true,
                    *sentFrom(),
                ))
                decodeOrNull<SessionItem>(reply["snapshot"])?.let { store.created(server, it) }
                store.drafts.remove(draft)
                started(SessionKey(server, id))
            } catch (e: Exception) {
                failed = e.message ?: "The server didn't answer."
            } finally {
                sending = false
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Wain.page).statusBarsPadding().navigationBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().height(60.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Wain.text) }
            BotTitle(bot) { editing = true }
        }
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState(), reverseScrolling = true).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Bottom),
        ) {
            for (line in bot.greeting ?: listOfNotNull(bot.welcome)) ReplyBubble(line)
        }
        failed?.let {
            Text("Couldn't send. ${sentence(it)}", Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp).clickable { failed = null },
                style = Wain.Font.footnote.copy(color = Wain.destructive))
        }
        val focus = ComposerFocus.key == draft
        LaunchedEffect(focus) { if (focus) ComposerFocus.key = null }
        Composer(draft, "Message ${bot.name}", busy = false, sending = sending, canSend = connected && !sending, send = ::send, focus = focus)
    }
    if (editing) BotSheet(editing = server to bot, close = { editing = false })
}
