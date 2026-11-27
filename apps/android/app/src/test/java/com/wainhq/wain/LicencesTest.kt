package com.wainhq.wain

import com.wainhq.wain.model.Licences
import java.io.File
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LicencesTest {
    // Gradle runs unit tests from the module directory, app/.
    private val licences = Licences.parse(File("src/main/assets/licences.json").readText())

    @Test
    fun everyEntryHasItsLicenceText() {
        assertTrue(licences.components.isNotEmpty())
        for (c in licences.components) assertNotNull("${c.name}: no ${c.licence} text", licences.licences[c.licence])
    }

    /**
     * shortcut: checks direct dependencies only, so a new transitive group slips past unless a
     * broader prefix covers it; rerun `gradlew :app:dependencies` when adding one.
     */
    @Test
    fun everyDirectDependencyHasAnEntry() {
        val groups = Regex("""^\s*(?:val \w+ = )?(?:implementation\()?platform\("([^:"]+):|^\s*implementation\("([^:"]+):""", RegexOption.MULTILINE)
            .findAll(File("build.gradle.kts").readText())
            .map { m -> m.groupValues.drop(1).first { it.isNotEmpty() } }
            .toList()
        assertTrue(groups.size > 10)
        val covers = licences.components.flatMap { it.covers }
        for (g in groups) assertTrue("$g ships with no entry in licences.json", covers.any { g.startsWith(it) })
    }
}
