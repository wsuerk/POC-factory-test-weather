package com.example.weather.architecture;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

@AnalyzeClasses(packages = "com.example.weather", importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureTest {

	@ArchTest
	static final ArchRule ONLY_WEB_DEPENDS_ON_WEB = noClasses()
		.that().resideOutsideOfPackage("com.example.weather.web..")
		.should().dependOnClassesThat().resideInAPackage("com.example.weather.web..")
		.allowEmptyShould(true);

	@ArchTest
	static final ArchRule NO_PACKAGE_CYCLES = slices()
		.matching("com.example.weather.(*)..")
		.should().beFreeOfCycles()
		.allowEmptyShould(true);

}
