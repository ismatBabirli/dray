package com.wainhq.wain

import com.wainhq.wain.model.BranchList
import com.wainhq.wain.model.CloneOffer
import com.wainhq.wain.model.Model
import com.wainhq.wain.model.Picks
import com.wainhq.wain.model.cloneOffers
import com.wainhq.wain.model.githubSlug
import com.wainhq.wain.store.ProjectChoice
import com.wainhq.wain.wire.Project
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    @Test fun clonesOfferOtherMachinesGithubReposThisOneLacksOncePerRepo() {
        val here = listOf(Project("/m/wain", "wain", remote = "github.com/acme/wain"), Project("/m/notes", "notes"))
        val offers = cloneOffers(here, listOf(
            "vps-1" to listOf(
                Project("/v/api", "api", remote = "github.com/acme/api"), Project("/v/wain", "wain", remote = "github.com/acme/wain"),
                Project("/v/scratch", "scratch"), Project("/v/lab", "lab", remote = "gitlab.com/acme/lab"),
            ),
            "studio" to listOf(Project("/s/api", "api", remote = "github.com/acme/api"), Project("/s/docs", "documentation", remote = "github.com/acme/docs")),
        ))
        assertEquals(listOf(CloneOffer("acme/api", "api", "vps-1"), CloneOffer("acme/docs", "docs", "studio")), offers)
        assertTrue(cloneOffers(here, emptyList()).isEmpty())
        assertEquals("octocat/hello-world", githubSlug("github.com/octocat/hello-world"))
        assertNull(githubSlug("gitlab.com/acme/lab"))
    }

    @Test fun startFromPutsTheDefaultBranchApartThenLocalThenRemote() {
        val b = BranchList("feat", listOf("main", "feat", "fix-login"), listOf("release"), "origin/main")
        assertEquals("main", b.defaultBranch)
        assertTrue(b.offersWorktreeBase)
        assertEquals(Triple("main", listOf("feat", "fix-login"), listOf("release")), b.worktreeOptions(""))
        assertEquals(Triple(null, listOf("fix-login"), emptyList<String>()), b.worktreeOptions("fi"))
        assertFalse(BranchList("main", listOf("main")).offersWorktreeBase)
    }
}
