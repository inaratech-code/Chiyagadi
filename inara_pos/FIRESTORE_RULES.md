# Firestore Security Rules

## Security Rules Configuration

Copy these rules to Firebase Console → Firestore → Rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isAuthenticated() {
      return request.auth != null;
    }
    
    // Helper function to check if user is owner
    function isOwner() {
      return request.auth != null && 
             resource.data.owner == request.auth.uid;
    }
    
    // Orders Collection
    // - Read: Authenticated users can read
    // - Write: Only owner can write (when syncing)
    match /orders/{orderId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false; // Never allow delete (audit trail)
    }
    
    // Payments Collection
    match /payments/{paymentId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false; // Never allow delete (audit trail)
    }
    
    // Purchases Collection
    match /purchases/{purchaseId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false; // Never allow delete (audit trail)
    }
    
    // Stock Transactions Collection
    match /stock_transactions/{transactionId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false; // Never allow delete (audit trail)
    }
    
    // Day Sessions Collection
    match /day_sessions/{sessionId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow update: if isAuthenticated();
      allow delete: if false; // Never allow delete (audit trail)
    }
    
    // Settings Collection (if used)
    match /settings/{settingId} {
      allow read: if isAuthenticated();
      allow write: if false; // Settings only in SQLite
    }
  }
}
```

## Simplified Rules (For Single Café)

If using Firebase Authentication is not configured, use these simpler rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow all operations for single-café use
    // In production, implement proper authentication
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

**Note:** The simplified rules are only for development/testing. For production, implement proper authentication and use the first set of rules.

## Deployment

1. Go to Firebase Console
2. Select your project
3. Navigate to Firestore Database → Rules
4. Paste the rules above
5. Click "Publish"

## Testing Rules

Use Firebase Console → Firestore → Rules → Rules Playground to test your rules.

## Best Practices

1. **Never allow deletes**: Maintain audit trail
2. **Timestamp validation**: Ensure timestamps match SQLite
3. **Data validation**: Validate required fields
4. **Owner field**: If multi-user, validate owner field
5. **Rate limiting**: Consider Cloud Functions for rate limiting
