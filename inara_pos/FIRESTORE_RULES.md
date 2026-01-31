# Firestore Security Rules

## Enable Email/Password sign-in (fix "Could not create login account")

If the app shows: *"Could not create login account for this email. Check that Email/Password sign-in is enabled in Firebase Console"*:

1. Open **[Firebase Console](https://console.firebase.google.com)** and select your project.
2. In the left sidebar, click **Authentication** (or **Build** → **Authentication**).
3. Open the **Sign-in method** tab.
4. Find **Email/Password** in the list.
5. Click it, turn **Enable** ON, then click **Save**.

After saving, try creating the user again in the app.

**Note:** This app uses **Email/Password** only. You can disable **Anonymous** sign-in if you don't need it (Authentication → Sign-in method → Anonymous → Disable). This avoids any potential conflicts.

---

## Fix "This domain is not authorized"

If the app shows: *"This domain is not authorized. In Firebase Console go to Authentication → Settings → Authorized domains and add your domain (e.g. localhost)."*:

1. Open **[Firebase Console](https://console.firebase.google.com)** and select your project.
2. In the left sidebar, click **Authentication** (or **Build** → **Authentication**).
3. Open the **Settings** tab (gear icon or "Settings" in the top menu).
4. Under **Authorized domains**, click **Add domain**.
5. Add your domain:
   - For local development: add `localhost`
   - For deployed app: add your domain (e.g. `your-app.web.app`, `your-domain.com`)
6. Click **Add** and save.

After adding the domain, try again in the app.

---

## Users and roles (login flow)

For **admin-set email/password** login to work:

1. **Firebase Authentication**: In Firebase Console → **Authentication** → **Sign-in method**, enable **Email/Password** (see steps above).
2. **Firestore `users` collection**: Each user document must have `email` (lowercase) and `role`. The app looks up the user by email after Firebase Auth sign-in to set `currentUserId` and `currentUserRole`.
3. **Firestore `roles` collection**: Used by the **Roles section** (Users & Roles → Roles tab) and for permission checks. The app seeds default `admin` and `cashier` roles when the collection is empty. Each document has: `name`, `description`, `permissions` (JSON array of section indices), `is_system_role`, `is_active`, `created_at`, `updated_at`. The app reads and writes this collection for create/edit/delete role and for `getRolePermissions`.
4. **Rules**: The app must be able to **read** and **write** `users` and `roles`. Use the Public Access Rules below so the app can read/write; or use Strict Rules and ensure `users` and `roles` allow read/write (e.g. `allow read, write: if request.auth != null`).

---

## Quick fix for "unidentified dataset" / permission-denied

If the app shows empty data, permission errors, or "unidentified dataset" on web:

1. Open **[Firebase Console](https://console.firebase.google.com)** → your project.
2. Go to **Firestore Database** → **Rules**.
3. Delete everything in the rules editor and paste **only** this:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

4. Click **Publish**. Wait a few seconds. Reload your app.

---

## Public Access Rules (same as above)

Copy this block into Firebase Console → Firestore Database → Rules, then click **Publish**.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

---

## Strict Rules (optional, for later when using Firebase Auth)

When you enable Firebase Authentication and want to restrict access, use this set instead:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function isOwner() {
      return request.auth != null && 
             resource.data.owner == request.auth.uid;
    }
    
    match /users/{userId} {
      allow read: if true;
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /orders/{orderId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /payments/{paymentId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /purchases/{purchaseId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /stock_transactions/{transactionId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /day_sessions/{sessionId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false;
    }
    
    match /settings/{settingId} {
      allow read: if isAuthenticated();
      allow write: if false;
    }
  }
}
```
## Deployment

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Open **Firestore Database** → **Rules**
4. Replace the entire rules editor content with the **Public Access Rules** block above
5. Click **Publish**

After publishing, the app should be able to read and write Firestore (users, orders, categories, products, etc.) and the "unidentified dataset" / permission-denied errors should stop.

## Testing Rules

Use Firebase Console → Firestore → Rules → Rules Playground to test your rules.

## Best Practices

1. **Never allow deletes**: Maintain audit trail
2. **Timestamp validation**: Ensure timestamps match SQLite
3. **Data validation**: Validate required fields
4. **Owner field**: If multi-user, validate owner field
5. **Rate limiting**: Consider Cloud Functions for rate limiting
