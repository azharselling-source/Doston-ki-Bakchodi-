# Ghar - setup (15 minute)

## 1. Firebase project (free)
1. console.firebase.google.com -> Add project (Analytics band kar do).
2. Build -> Authentication -> Get started -> Sign-in method -> **Email/Password** ON.
3. Build -> Firestore Database -> Create database (production mode) -> Rules tab me ye paste karo aur Publish:

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{u} {
      allow read: if request.auth != null;
      allow write: if request.auth != null && request.auth.uid == u;
    }
    match /clips/{c} {
      allow read: if request.auth != null;
      allow create: if request.auth != null && request.resource.data.from == request.auth.uid;
    }
  }
}
```
4. Project settings (gear) -> Your apps -> **Android icon** -> package name: `com.azhar.ghar` -> Register app.
5. Wahan se google-services.json download karo aur kholo. Ye 4 values chahiye:
   - apiKey = `current_key`
   - appId = `mobilesdk_app_id`
   - messagingSenderId = `project_number`
   - projectId = `project_id`
6. `lib/main.dart` ke upar `firebaseOptions` me ye 4 values paste karo. `groupCode` bhi badal lo.

## 2. APK banao
1. GitHub par nayi repo banao aur ye saari files push karo (`.github` folder samet).
2. Repo -> Actions tab -> "Build APK" khud chalega (ya Run workflow).
3. 5-8 minute baad run kholo -> neeche Artifacts -> **ghar-apk** download karo -> zip khol kar app-release.apk dosto ko bhej do.

## 3. Pehli baar
Sab dost "Naya account" se apna naam, password aur group code daal kar account banayen.

## Optional: purani clips khud delete hon
Firestore -> Indexes -> TTL -> Create policy: collection `clips`, field `expireAt`.
