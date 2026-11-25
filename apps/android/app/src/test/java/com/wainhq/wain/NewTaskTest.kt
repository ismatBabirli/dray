package com.wainhq.wain

import com.wainhq.wain.model.Model
import com.wainhq.wain.model.Picks
import com.wainhq.wain.store.ProjectChoice
import org.junit.Assert.assertEquals
import org.junit.Test

class NewTaskTest {
    private val models = listOf(Model("fable"), Model("opus"), Model("haiku"))

    @Test fun usableModelKeepsAPickTheListHas() = assertEquals("haiku", Picks.usableModel(models, "haiku", "claude_code"))

    @Test fun usableModelFallsToTheHarnessDefaultNotTheHead() = assertEquals("opus", Picks.usableModel(models, "gone", "claude_code"))

    @Test fun usableModelTakesTheHeadOnlyWithoutTheDefault() =
        assertEquals("fable", Picks.usableModel(listOf(Model("fable"), Model("haiku")), "gone", "claude_code"))

    @Test fun usableModelLeavesAnEmptyDefaultToTheHarness() = assertEquals("", Picks.usableModel(models, "gone", "pi"))

    @Test fun usableModelStandsWhileTheListIsUnread() = assertEquals("gone", Picks.usableModel(emptyList(), "gone", "claude_code"))

    @Test fun projectChoiceNamesTheFolderAboveOnlyWhenSplit() {
        assertEquals("wain", ProjectChoice("wain", null).label)
        assertEquals("wain — work", ProjectChoice("wain", "/home/me/work/wain").label)
    }
}
