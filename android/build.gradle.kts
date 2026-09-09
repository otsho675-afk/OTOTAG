subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            (androidExt as com.android.build.gradle.BaseExtension).compileSdkVersion(36)
        }
    }
}