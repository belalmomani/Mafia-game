import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// الأولوية: local.properties ثم متغيرات البيئة (GitHub secrets) ثم supabase.properties (المرفوع في المستودع).
fun loadProps(file: String) = Properties().apply {
    val f = rootProject.file(file)
    if (f.exists()) f.inputStream().use { load(it) }
}
val localProps = loadProps("local.properties")
val sharedProps = loadProps("supabase.properties")
fun cfg(name: String): String =
    localProps.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: System.getenv(name)?.takeIf { it.isNotBlank() }
        ?: sharedProps.getProperty(name)?.trim().orEmpty()

android {
    namespace = "com.mafia.game"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.mafia.game"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        // المفتاح العام (publishable/anon) فقط. ممنوع وضع service_role أو secret key هنا.
        buildConfigField("String", "SUPABASE_URL", "\"${cfg("SUPABASE_URL")}\"")
        buildConfigField("String", "SUPABASE_PUBLISHABLE_KEY", "\"${cfg("SUPABASE_PUBLISHABLE_KEY")}\"")
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.00")
    implementation(composeBom)
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Start.io (StartApp) — بانر إعلاني صغير أسفل الشاشة
    implementation("com.startapp:inapp-sdk:5.+")
}
