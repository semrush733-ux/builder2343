
// ---- B1G: pack only the processor types this build is for (keeps the APK small) ----
val b1gAbis: String? = System.getenv("B1G_ABIS")
if (!b1gAbis.isNullOrBlank()) {
    android {
        defaultConfig {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(b1gAbis.split(",").map { it.trim() })
            }
        }
    }
}

// ---- B1G: FileProvider (hands the downloaded update to Android's installer) ----
dependencies {
    implementation("androidx.core:core:1.13.1")
}
