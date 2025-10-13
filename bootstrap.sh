set -e
rm -rf app gradle .gradle build .idea .github || true
mkdir -p app/src/main/java/com/bendlayout app/src/main/res .github/workflows

# settings.gradle.kts (includes google() for plugins!)
cat > settings.gradle.kts <<'EOF'
import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "BendLayout"
include(":app")
EOF

# top-level build.gradle.kts (stable combo that works in Termux)
cat > build.gradle.kts <<'EOF'
plugins {
    id("com.android.application") version "8.6.1" apply false
    kotlin("android") version "2.0.20" apply false
}
EOF

# gradle.properties
cat > gradle.properties <<'EOF'
org.gradle.jvmargs=-Xmx2g -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
org.gradle.caching=true
org.gradle.configuration-cache=true
EOF

# app/build.gradle.kts
cat > app/build.gradle.kts <<'EOF'
plugins {
    id("com.android.application")
    kotlin("android")
}
android {
    namespace = "com.bendlayout"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.bendlayout"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        vectorDrawables { useSupportLibrary = true }
    }
    buildTypes {
        debug { isMinifyEnabled = false }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.15" }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.00"))
    implementation("androidx.activity:activity-compose")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
EOF

# proguard
cat > app/proguard-rules.pro <<'EOF'
-keep class androidx.** { *; }
-dontwarn kotlin.**
EOF

# manifest
cat > app/src/main/AndroidManifest.xml <<'EOF'
<manifest package="com.bendlayout" xmlns:android="http://schemas.android.com/apk/res/android">
  <application
    android:allowBackup="true"
    android:label="Bend Layout"
    android:supportsRtl="true"
    android:theme="@style/Theme.Material3.DayNight.NoActionBar">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

# MainActivity (Y-B-C math)
cat > app/src/main/java/com/bendlayout/MainActivity.kt <<'EOF'
package com.bendlayout

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import kotlin.math.PI

data class BendInput(var angleDeg: String = "", var rotationDeg: String = "0", var straightToNext: String = "0")
data class BendCalcRow(val index: Int, val yStart: Double, val bAngle: Double, val cRot: Double)

class MainActivity : ComponentActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setContent { MaterialTheme { Surface(Modifier.fillMaxSize()) { BendLayoutScreen() } } }
  }
}

@Composable
fun BendLayoutScreen() {
  var units by remember { mutableStateOf("in") }
  var tubeOD by remember { mutableStateOf("") }
  var clr by remember { mutableStateOf("") }
  var springback by remember { mutableStateOf("0") }
  var startStraight by remember { mutableStateOf("") }
  var endStraight by remember { mutableStateOf("") }
  var bends by remember { mutableStateOf(listOf(BendInput())) }
  var results by remember { mutableStateOf<List<BendCalcRow>>(emptyList()) }
  var totalCut by remember { mutableStateOf<Double?>(null) }
  var errorMsg by remember { mutableStateOf<String?>(null) }

  fun parseD(s: String): Double = s.trim().toDoubleOrNull() ?: Double.NaN

  fun calc() {
    errorMsg = null; results = emptyList(); totalCut = null
    val clrV = parseD(clr)
    val sb = parseD(springback).let { if (it.isNaN()) 0.0 else it }
    val startV = parseD(startStraight)
    val endV = parseD(endStraight)
    if (listOf(clrV, startV, endV).any { it.isNaN() || it < 0.0 }) { errorMsg = "Enter valid CLR, Start Straight, End Straight."; return }

    val parsed = mutableListOf<Triple<Double, Double, Double>>()
    for (b in bends) {
      val a = parseD(b.angleDeg)
      val r = parseD(b.rotationDeg).let { if (it.isNaN()) 0.0 else it }
      val sNext = parseD(b.straightToNext).let { if (it.isNaN()) 0.0 else it }
      if (a.isNaN() || a <= 0.0) { errorMsg = "Each bend needs angle > 0."; return }
      if (sNext < 0.0) { errorMsg = "Straight-to-next cannot be negative."; return }
      parsed += Triple(a, r, sNext)
    }

    val out = mutableListOf<BendCalcRow>()
    var y = startV
    var cut = startV + endV

    parsed.forEachIndexed { idx, (ang, rot, sNext) ->
      out += BendCalcRow(index = idx + 1, yStart = y, bAngle = ang + sb, cRot = rot)
      val arcLen = clrV * (ang * PI / 180.0)
      y = y + arcLen + sNext
      cut += arcLen + sNext
    }
    results = out; totalCut = cut
  }

  LazyColumn(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
    item {
      Text("Bend Layout Calculator", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
      Spacer(Modifier.height(6.dp)); Text("Centerline-true YBC marks, per-bend arcs, and total cut length.")
    }
    item {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SegBtn(units == "in", "in") { units = "in" }
        SegBtn(units == "mm", "mm") { units = "mm" }
      }
    }
    item {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NumField("Tube OD ($units)", tubeOD) { tubeOD = it }
        NumField("CLR ($units) *required", clr) { clr = it }
        NumField("Springback add (°)", springback) { springback = it }
      }
    }
    item {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        NumField("Start straight ($units)", startStraight) { startStraight = it }
        NumField("End straight ($units)", endStraight) { endStraight = it }
      }
    }
    itemsIndexed(bends) { idx, b ->
      Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
          Text("Bend ${idx + 1}", fontWeight = FontWeight.SemiBold)
          Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            NumField("Angle θ (°)", b.angleDeg) { bends = bends.toMutableList().apply { this[idx] = this[idx].copy(angleDeg = it) } }
            NumField("Rotation C (°)", b.rotationDeg) { bends = bends.toMutableList().apply { this[idx] = this[idx].copy(rotationDeg = it) } }
            NumField("Straight to next S ($units)", b.straightToNext) { bends = bends.toMutableList().apply { this[idx] = this[idx].copy(straightToNext = it) } }
          }
          Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { bends = bends.toMutableList().apply { add(idx + 1, BendInput()) } }) { Text("Add bend after") }
            if (bends.size > 1) {
              OutlinedButton(onClick = { bends = bends.toMutableList().apply { removeAt(idx) } }) { Text("Remove bend") }
            }
          }
        }
      }
    }
    item {
      Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Button(onClick = { bends = listOf(BendInput()) }) { Text("Clear bends") }
        Button(onClick = { calc() }) { Text("Calculate") }
      }
    }
    item { errorMsg?.let { Text(it, color = MaterialTheme.colorScheme.error) } }
    if (results.isNotEmpty()) {
      item { Text("YBC / Tangent Marks", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold) }
      itemsIndexed(results) { _, row ->
        Text("Bend ${row.index}:  Y = ${"%.4f".format(row.yStart)} $units,   B = ${"%.4f".format(row.bAngle)}°,   C = ${"%.4f".format(row.cRot)}°")
      }
    }
    item { totalCut?.let { Spacer(Modifier.height(8.dp)); Text("Total cut length: ${"%.4f".format(it)} $units", fontWeight = FontWeight.Bold) } }
    item { Spacer(Modifier.height(32.dp)) }
  }
}

@Composable
fun NumField(label: String, value: String, onChange: (String) -> Unit) {
  OutlinedTextField(
    value = value, onValueChange = onChange, label = { Text(label) },
    modifier = Modifier.weight(1f),
    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal)
  )
}

@Composable
fun SegBtn(selected: Boolean, text: String, onClick: () -> Unit) {
  FilledTonalButton(onClick = onClick) { Text(text) }
}
EOF

# GitHub Actions (cloud build)
cat > .github/workflows/android.yml <<'EOF'
name: Android CI (APK + AAB)
on:
  workflow_dispatch:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'
          cache: 'gradle'
      - uses: android-actions/setup-android@v3
        with:
          packages: |
            platforms;android-35
            build-tools;35.0.0
            platform-tools
      - uses: gradle/wrapper-validation-action@v2
      - uses: gradle/actions/setup-gradle@v3
      - name: Build Debug APK
        run: ./gradlew :app:assembleDebug
      - name: Build Release (unsigned) APK & AAB
        run: |
          ./gradlew :app:assembleRelease
          ./gradlew :app:bundleRelease
      - uses: actions/upload-artifact@v4
        with:
          name: BendLayout-artifacts
          path: |
            app/build/outputs/apk/**/app-*.apk
            app/build/outputs/bundle/**/app-*.aab
          if-no-files-found: error
EOF

# gitignore
cat > .gitignore <<'EOF'
/.gradle
/build
/local.properties
/.idea
/app/build
/captures
.externalNativeBuild
*.keystore
*.jks
*.keystore.properties
EOF

echo "Writing local.properties"
echo "sdk.dir=$HOME/android-sdk" > local.properties
