# Face Attendance App (face_att)

A robust and secure Flutter application for handling facial recognition-based attendance. The project utilizes Google ML Kit for face detection and TensorFlow Lite for face recognition and embeddings extraction, running fully on-device for maximum privacy and performance.

## 🌟 Features
- **Face Detection:** Real-time face detection using Google ML Kit.
- **Face Recognition:** Uses custom TensorFlow Lite (TFLite) models to identify users based on their facial embeddings.
- **Local Storage:** Secure, fast local storage for caching and storing user embedding vectors utilizing `hive_flutter`.
- **Animations:** High-quality Lottie animations for loading states and user feedback.
- **Image Processing:** Efficient image manipulation using the `image` package to process camera frames.

## 🛠 Tech Stack
- **Framework:** [Flutter](https://flutter.dev/)
- **Machine Learning:** `tflite_flutter`, `google_ml_kit`
- **Camera:** `camera` plugin for live feed.
- **Storage:** `hive_flutter` (NoSQL Key-Value database).
- **UI/UX:** `lottie` for animations, `cupertino_icons` for iOS style icons.

---

## 🚀 Running the Project

Follow these steps to run the application on your local machine:

### Prerequisites
1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install) (Ensure you are on the `stable` channel).
2. Install Android Studio (for Android development/emulators) or Xcode (for iOS).
3. Connect a physical device or start an emulator. Note: **Physical devices are highly recommended** for camera and ML performance testing.

### Setup Steps
1. **Clone/Navigate to the project directory:**
   ```bash
   cd /path/to/face_att
   ```

2. **Fetch Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the App:**
   ```bash
   flutter run
   ```
   *To run in release mode for maximum performance:*
   ```bash
   flutter run --release
   ```

---

## 🛡️ ProGuard Rules Configuration

When building the Android app for Release (e.g., using `flutter build apk` or `flutter build appbundle`), Android's R8 compiler automatically minifies and obfuscates the code to reduce app size and protect intellectual property.

However, obfuscation can break packages that rely on reflection or JNI (Java Native Interface), such as `tflite_flutter`, `google_ml_kit`, and `hive`. To prevent the compiler from stripping away crucial classes, we add custom **ProGuard Rules**.

### Where are the rules added?
The rules are defined in `android/app/proguard-rules.pro`. The file is linked in `android/app/build.gradle` inside the `release` block:
```gradle
buildTypes {
    release {
        signingConfig signingConfigs.debug
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

### Key ProGuard Rules Added
We keep classes required for Flutter, TFLite, ML Kit, and Hive intact:
```proguard
# TFLite
-keep class org.tensorflow.** { *; }
-keepclassmembers class org.tensorflow.** { *; }

# ML Kit 
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

# Hive
-keep class com.hive.** { *; }
-keepclassmembers class * {
    @com.hive.annotations.HiveField *;
}
```

---

## ⚙️ Why Add `jniLibs`?

You might notice configurations or references to **JNI (Java Native Interface) Libraries** (`jniLibs`) in Android ML projects. Here is why they are crucial for this application:

### 1. What are JNI Libraries?
`jniLibs` contain pre-compiled native code (usually written in C or C++) that allows Java/Kotlin code to interact with native hardware directly. These files usually have the `.so` extension (e.g., `libtensorflowlite_jni.so`).

### 2. Why does `face_att` need them?
- **TensorFlow Lite (`tflite_flutter`):** The core TFLite engine is written in C++ for maximum execution speed across different CPU architectures (ARM, x86). The `jniLibs` act as a bridge between the Dart/Flutter code and the underlying high-performance C++ TFLite engine.
- **Google ML Kit:** Similar to TFLite, the heavy lifting for image processing and computer vision algorithms in ML Kit is done natively via C++.
- **Performance:** Running complex matrix multiplications and neural network inference natively is vastly faster than running it through a virtual machine or interpreted language.

### 3. CPU Architectures
When building the app, `jniLibs` are often bundled for different Android architectures to ensure compatibility across devices:
- `armeabi-v7a` (Older 32-bit ARM devices)
- `arm64-v8a` (Modern 64-bit ARM devices - *Most common today*)
- `x86_64` (64-bit Android Emulators)

If you encounter an issue like `"UnsatisfiedLinkError: dlopen failed: library not found"`, it usually means the correct `.so` file for the specific device's CPU architecture is missing from the `jniLibs` bundle.
