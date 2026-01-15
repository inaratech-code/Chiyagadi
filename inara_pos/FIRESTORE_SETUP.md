# Firestore Database Setup Guide

## ⚠️ Database Initialization Error Fix

If you're seeing the error: **"Database initialization failed after 3 attempts"**, it means Firestore Database is not enabled in your Firebase Console.

## Step-by-Step: Enable Firestore Database

### 1. Go to Firebase Console
- Visit: https://console.firebase.google.com/
- Select your project: **chiyagadi-cf302**

### 2. Enable Firestore Database
1. In the left sidebar, click **"Firestore Database"** (or "Build" → "Firestore Database")
2. Click **"Create database"** button
3. Choose **"Start in test mode"** (for development)
   - ⚠️ **Important**: Test mode allows read/write access for 30 days. You'll need to update security rules later.
4. Select a **location** (choose the closest to your users)
   - Recommended: `us-central1`, `asia-south1`, or `europe-west1`
5. Click **"Enable"**

### 3. Configure Security Rules (Important!)

After enabling, you need to set up security rules:

1. Go to **Firestore Database** → **Rules** tab
2. Choose one of the following rule sets:

#### Option A: Development/Testing Rules (Quick Setup)

⚠️ **Warning**: These rules allow public access. Use only for development or if your app is only accessible on a private network.

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to all documents (for development only)
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

#### Option B: More Secure Rules (Recommended for Production)

These rules provide better security while still allowing the app to work without authentication:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Settings: Read for all, write restricted
    match /settings/{settingId} {
      allow read: if true;
      allow write: if request.resource.data.keys().hasAll(['key', 'value', 'updated_at']);
    }
    
    // Users: Full access (for PIN-based auth)
    match /users/{userId} {
      allow read, write: if true;
    }
    
    // Orders: Read/write allowed (add authentication later)
    match /orders/{orderId} {
      allow read, write: if true;
      // Prevent deletion (maintain audit trail)
      allow delete: if false;
    }
    
    // Products: Read for all, write allowed
    match /products/{productId} {
      allow read: if true;
      allow write: if true;
      allow delete: if false; // Prevent deletion
    }
    
    // Categories: Read for all, write allowed
    match /categories/{categoryId} {
      allow read: if true;
      allow write: if true;
      allow delete: if false;
    }
    
    // Customers: Read/write allowed
    match /customers/{customerId} {
      allow read, write: if true;
      allow delete: if false;
    }
    
    // Other collections: Allow read/write but prevent deletion
    match /{collection}/{documentId} {
      allow read, write: if true;
      allow delete: if false; // Maintain audit trail
    }
  }
}
```

**Benefits of Option B:**
- Prevents accidental deletion (maintains audit trail)
- Validates data structure for settings
- More organized and maintainable
- Easier to add authentication later

3. Click **"Publish"** (not just Save)

⚠️ **Important**: 
- For **local/private network use**: Option A is fine
- For **public web deployment**: Use Option B or implement Firebase Authentication
- The warning you see is expected with these rules - it's informing you that the database is publicly accessible

### 4. Test Your App

After enabling Firestore:
1. Refresh your Flutter web app
2. The database initialization should now succeed
3. You should be able to login and use the app

## Verify Firestore is Working

### Step 1: Check if Settings Collection Exists

1. Go to Firebase Console → Firestore Database → **Data** tab
2. After the app initializes successfully, you should see:
   - **`settings`** collection (created automatically during initialization)
   - Inside `settings`, you should see documents like:
     - `cafe_name`
     - `cafe_name_en`
     - `tax_percent`
     - `discount_enabled`
     - etc.

### Step 2: Other Collections Appear When You Use Features

Other collections are created **only when you use those features** in the app:
- **`users`** - Created when you set up admin PIN/login
- **`products`** - Created when you add products
- **`orders`** - Created when you create orders
- **`categories`** - Created when you add categories
- **`customers`** - Created when you add customers
- etc.

### Step 3: If You Don't See the `settings` Collection

If you don't see the `settings` collection, it means:
1. **Database initialization failed** - Check browser console (F12) for errors
2. **Firestore rules are blocking writes** - Make sure you published the security rules
3. **App hasn't initialized yet** - Try refreshing the app or clicking "Setup & Login"

### Quick Test

1. Open your app in the browser
2. Open browser console (F12 → Console tab)
3. Look for messages like:
   - `FirestoreDatabase: Firestore initialized successfully`
   - `FirestoreDatabase: Default settings created`
4. If you see errors, they will tell you what's wrong

## Troubleshooting: Can't See Collections

### If you don't see ANY collections in Firestore:

1. **Check if Firestore is enabled:**
   - Go to Firebase Console → Firestore Database
   - If you see "Create database" button, click it and follow Step 2 above
   - If you see the Data tab but it's empty, continue to step 2

2. **Check browser console for errors:**
   - Open your app in browser
   - Press F12 to open Developer Tools
   - Go to "Console" tab
   - Look for error messages (red text)
   - Common errors:
     - `PERMISSION_DENIED` → Security rules not set correctly
     - `Firestore database is not enabled` → Need to create database
     - `Failed to get document` → Connection issue

3. **Verify initialization succeeded:**
   - In browser console, look for these messages:
     - ✅ `FirestoreDatabase: Firestore initialized successfully`
     - ✅ `FirestoreDatabase: Default settings created`
   - If you see ❌ `FirestoreDatabase: Initialization failed`, check the error message

4. **Test Firestore connection manually:**
   - In Firebase Console → Firestore Database → Data tab
   - Click "Start collection"
   - Collection ID: `test`
   - Document ID: `test1`
   - Add a field: `name` (string) = `test`
   - Click "Save"
   - If this works, Firestore is enabled correctly

5. **Check security rules:**
   - Go to Firestore Database → Rules tab
   - Make sure rules are published (not just saved)
   - For testing, use: `allow read, write: if true;`

## Common Issues

### Issue: "Missing or insufficient permissions"
**Solution**: 
- Go to Firestore Database → Rules tab
- Update rules to allow access (see Step 3 above)
- Click "Publish" (not just "Save")

### Issue: "Firestore database is not enabled"
**Solution**: 
- Go to Firebase Console → Firestore Database
- Click "Create database" if you see the button
- Follow Step 2 above

### Issue: Still getting initialization errors
**Solution**: 
1. Check browser console (F12) for detailed error messages
2. Verify Firebase configuration in `lib/firebase_options.dart` matches your Firebase project
3. Make sure you're using the correct Firebase project ID
4. Try clearing browser cache and refreshing

## Understanding the Security Warning

When you see the warning: **"Your security rules are defined as public"**, this means:

### What It Means:
- Anyone with your Firebase project configuration can access your database
- This is **expected** if you're using the development rules above
- The warning is Firebase's way of alerting you to potential security risks

### When Is This Acceptable?

✅ **OK for:**
- Development/testing on localhost
- Private network deployments (not accessible from internet)
- Single-café internal use (if network is secure)
- Learning/prototyping

❌ **NOT OK for:**
- Public web apps accessible from the internet
- Production deployments with sensitive data
- Multi-user systems without proper access control

### How to Reduce Risk (Without Authentication):

1. **Use Option B rules** (from Step 3) - Prevents deletion, validates data
2. **Restrict Firebase API key** - In Firebase Console → Project Settings → API Keys, restrict the web API key to specific domains
3. **Use Firebase App Check** - Add an extra layer of protection
4. **Monitor usage** - Check Firebase Console → Firestore → Usage for unusual activity

### For Production (Recommended):

Implement Firebase Authentication and use these rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Helper function
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Users: Only authenticated users
    match /users/{userId} {
      allow read, write: if isAuthenticated();
    }
    
    // Orders: Authenticated users only
    match /orders/{orderId} {
      allow read, write: if isAuthenticated();
      allow delete: if false; // Never delete
    }
    
    // Products: Read for all, write for authenticated
    match /products/{productId} {
      allow read: if true;
      allow write: if isAuthenticated();
      allow delete: if false;
    }
    
    // Settings: Read for all, write for authenticated
    match /settings/{settingId} {
      allow read: if true;
      allow write: if isAuthenticated();
    }
  }
}
```

## Need Help?

If you're still having issues:
1. Check the browser console (F12) for detailed error messages
2. Verify your Firebase project ID matches in `firebase_options.dart`
3. Make sure Firestore Database is enabled and security rules are published
4. The security warning is **normal** for development - you can dismiss it for now