# Third-party components

Thor Monitor uses these pinned components for local wireless-debugging recovery. They are not used to connect to remote devices; the recovery connection is restricted to 127.0.0.1. Library binary checksums are in SHA256SUMS.

- LibADB Android 3.1.1 — Muntashir Al-Islam. Apache-2.0 (selected from the upstream Apache-2.0 / GPL-3.0-or-later dual license). https://github.com/MuntashirAkon/libadb-android/tree/3.1.1
- SPAKE2 Java / Android 2.2.1 — Muntashir Al-Islam. LGPL-3.0-or-later. https://github.com/MuntashirAkon/spake2-java/tree/2.2.1
- SPAKE2 C — revision 0d15933e5ba3e662cb01245a7ac0dc9fca3eac31. Native source and upstream license are included in source/spake2-c-0d15933.zip.
- Conscrypt Android 2.5.3 — The Android Open Source Project / Google. Apache-2.0, including upstream third-party notices. https://github.com/google/conscrypt/tree/2.5.3
- Bouncy Castle bcprov-jdk15to18 1.81 — The Legion of the Bouncy Castle Inc. Bouncy Castle license (MIT-style). https://www.bouncycastle.org/licence.html
- AndroidX Annotation JVM 1.9.1 — The Android Open Source Project. Apache-2.0. https://android.googlesource.com/platform/frameworks/support/+/androidx-main/annotation/

The original SPAKE2 Java and native source archives are provided under source/, together with the app source and build script. The application can be rebuilt and re-signed with replacement library binaries; no signature or integrity restriction prevents this. Copyright, LGPL-3.0 and GPL-3.0 notices accompany the source. No OEM APKs, decompiled OEM sources, private recovery identities or development signing keys are included.
