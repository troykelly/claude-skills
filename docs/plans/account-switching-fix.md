# Plan: Fix Account Switching Token Invalidation

## Status: Analysis Complete - Root Cause Identified

### Key Finding: Tokens Are Server-Side Bound and May Be Invalidated on New Login

Tokens use Anthropic's proprietary format (NOT JWTs):
- Access tokens: `sk-ant-oat01-...`
- Refresh tokens: `sk-ant-ort01-...`

| Account | Access Token (prefix) | Expires At |
|---------|----------------------|------------|
| Account ONE (troy+...) | `sk-ant-oat01-uQ80ny...` | 1767593762950 |
| Account TWO (claude.ai@...) | `sk-ant-oat01-r1J4ap...` | 1767593837934 |

**Server-Side Token Binding**: The server maintains a lookup table mapping each token to its account. These are opaque tokens - we cannot decode them to see their claims.

### Root Cause Hypothesis: Single-Session Enforcement

**Most Likely Cause**: When logging into Account B, the backend may **automatically invalidate Account A's token** as a security measure (single-session-per-device enforcement).

Sequence of events:
1. Log in as Account A → receive token T_A ✓
2. Capture token T_A to .env ✓
3. Log in as Account B → receive token T_B, **T_A is invalidated by backend** ✗
4. Capture token T_B to .env ✓
5. Run `claude-account switch` to Account A → restore T_A
6. API call with T_A fails because **T_A was already invalidated in step 3**

### What Normal Login Changes (Evidence from Account Comparison)

Comparing the two tgz files showing Account ONE → Account TWO transition:

| Field | Account ONE | Account TWO | Changed? |
|-------|-------------|-------------|----------|
| `numStartups` | 1 | 2 | ✓ Incremented |
| `oauthAccount` | Account A | Account B | ✓ Expected |
| `anonymousId` | Not present | `claudecode.v1...` | ✓ Added |
| `lastSessionId` | `34837e40-...` | `5a5af748-...` | ✓ Changed |
| `lastModelUsage` | Has data | `{}` | ✓ Reset |
| `userID` | `a64e4b2c...` | `a64e4b2c...` | ✗ Same (device ID) |
| `hasShownOpus45Notice` | `{00f79fc5: true}` | `{00f79fc5: true}` | ✗ Same (old org!) |
| `s1mAccessCache` | `{00f79fc5: {...}}` | `{00f79fc5: {...}}` | ✗ Same (old org!) |
| `passesEligibilityCache` | `{00f79fc5: {...}}` | `{00f79fc5: {...}}` | ✗ Same (old org!) |
| Session files in `projects/` | Present | **Preserved** | ✗ NOT cleared |

**Critical Finding**: The org-keyed caches (`hasShownOpus45Notice`, `s1mAccessCache`, `passesEligibilityCache`) in Account TWO's config **still reference Account ONE's organizationUuid** (`00f79fc5-...`). This proves:
1. Claude Code does NOT clear these caches during normal login
2. Cache staleness is NOT the cause of token invalidation
3. Session state preservation is CORRECT behavior

### What `capture_account()` Saves vs What `switch_account()` Restores

Both are properly aligned:

| Field | Captured | Restored | Match? |
|-------|----------|----------|--------|
| emailAddress | ✓ | ✓ | ✓ |
| accountUuid | ✓ | ✓ | ✓ |
| organizationUuid | ✓ | ✓ | ✓ |
| displayName | ✓ | ✓ | ✓ |
| organizationName | ✓ | ✓ | ✓ |
| organizationRole | ✓ | ✓ | ✓ |
| hasExtraUsageEnabled | ✓ | ✓ | ✓ |
| workspaceRole | Not captured | Set to null | ✓ (usually null) |
| accessToken | ✓ | ✓ | ✓ |
| refreshToken | ✓ | ✓ | ✓ |
| expiresAt | ✓ | ✓ | ✓ |
| scopes | ✓ | ✓ | ✓ |
| subscriptionType | ✓ | ✓ | ✓ |
| rateLimitTier | ✓ | ✓ | ✓ |

The metadata being restored is complete and correct.

---

## Proposed Solutions (Updated Based on Analysis)

### Option A: Token Refresh on Switch (RECOMMENDED)

**Theory**: Since access tokens may be invalidated when a different account logs in, use the **refresh token** to obtain a fresh access token immediately after switching.

**Why This Should Work**:
- The refresh token should remain valid even if the access token was invalidated
- OAuth refresh tokens are designed for exactly this use case
- This is how the official OAuth flow would re-authenticate

**Implementation**:
```bash
switch_account() {
  # ... existing switch logic ...

  # After restoring credentials from .env:
  local refresh_token
  refresh_token=$(get_account_field "$new_email" "REFRESHTOKEN")

  # Attempt to refresh the access token
  local refresh_response
  refresh_response=$(curl -s -X POST "https://console.anthropic.com/api/auth/oauth/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=refresh_token&refresh_token=${refresh_token}")

  # If successful, update with fresh access token
  if echo "$refresh_response" | jq -e '.access_token' >/dev/null 2>&1; then
    local new_access_token new_expires_at
    new_access_token=$(echo "$refresh_response" | jq -r '.access_token')
    new_expires_at=$(echo "$refresh_response" | jq -r '.expires_at')
    # Update stored credentials with fresh token
  fi
}
```

**Risk**: Need to discover the correct refresh endpoint and request format.

---

### Option B: Re-Capture After Fresh Login (Workaround)

**Theory**: Accept that tokens are invalidated on new login. The workflow becomes:
1. Log in to Account A → capture
2. Log in to Account B → capture (Account A's token now invalid)
3. When switching back to Account A, prompt user to re-login and re-capture

**Implementation**:
```bash
switch_account() {
  # Try to use existing token first
  if ! verify_token "$access_token"; then
    echo "Token expired or invalid. Please run: claude"
    echo "After logging in, run: claude-account capture"
    exit 1
  fi
}
```

**Pros**: Simple, reliable, no API guessing
**Cons**: Requires user interaction for each switch

---

### Option C: Pre-Emptive Token Refresh on Capture

**Theory**: When capturing an account, immediately refresh the token and store the FRESH tokens. This gives us the longest possible validity window.

**Implementation**:
```bash
capture_account() {
  # ... existing capture logic ...

  # After getting current credentials, immediately refresh
  local fresh_tokens
  fresh_tokens=$(refresh_oauth_token "$refresh_token")

  # Store the FRESH tokens, not the current ones
  update_env_line "${prefix}_ACCESSTOKEN" "$(echo "$fresh_tokens" | jq -r '.access_token')"
  update_env_line "${prefix}_EXPIRESAT" "$(echo "$fresh_tokens" | jq -r '.expires_at')"
}
```

**Pros**: Maximizes token validity
**Cons**: Doesn't solve the invalidation-on-new-login problem

---

### Option D: Verify Token Before Use (Defensive)

**Theory**: Before switching, verify the target account's token is still valid. If not, inform user.

**Implementation**:
```bash
switch_account() {
  local access_token
  access_token=$(get_account_field "$new_email" "ACCESSTOKEN")

  # Test the token against a lightweight API endpoint
  local verify_response
  verify_response=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer $access_token" \
    "https://api.anthropic.com/v1/me")

  if [[ "$verify_response" == "401" ]]; then
    echo "Token for $new_email is invalid or expired."
    echo "Please log in to this account and re-capture."
    exit 1
  fi

  # Proceed with switch...
}
```

**Pros**: Fails fast with clear error message
**Cons**: Doesn't fix the underlying issue

---

## Research Findings (Verified 2026-01-05)

### Token Refresh Endpoint

**Endpoint**: `POST https://console.anthropic.com/v1/oauth/token`

**Request**:
```bash
curl -s -X POST "https://console.anthropic.com/v1/oauth/token" \
  -H "Content-Type: application/json" \
  -d '{
    "grant_type": "refresh_token",
    "refresh_token": "sk-ant-ort01-...",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  }'
```

**Response** (HTTP 200):
```json
{
  "token_type": "Bearer",
  "access_token": "sk-ant-oat01-...",
  "expires_in": 28800,
  "refresh_token": "sk-ant-ort01-...",
  "scope": "user:inference user:profile user:sessions:claude_code",
  "organization": {"uuid": "...", "name": "..."},
  "account": {"uuid": "...", "email_address": "..."}
}
```

**Key Findings**:
- Access tokens expire after 8 hours (28800 seconds)
- A NEW refresh token is returned with each refresh - must update stored token
- The refresh token survives across account logins (verified)

### Token Verification Endpoint

**Endpoint**: `GET https://api.anthropic.com/api/oauth/usage`

**Request**:
```bash
curl -s -H "Authorization: Bearer sk-ant-oat01-..." \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage"
```

**Response** (HTTP 200 if valid, 401 if invalid):
```json
{
  "five_hour": {"utilization": 12.0, "resets_at": "..."},
  "seven_day": {"utilization": 76.0, "resets_at": "..."},
  "extra_usage": {"is_enabled": true, "monthly_limit": 20000, ...}
}
```

**Note**: The standard `/v1/models` API endpoint does NOT work for OAuth tokens - returns 401.

---

## Recommended Implementation Order

### Phase 1: Understand Token Refresh (Research) - COMPLETE

1. **Find the OAuth token refresh endpoint** ✓
   - Verified: `https://console.anthropic.com/v1/oauth/token`
   - Uses JSON body, not form-encoded
   - Requires client_id: `9d1c250a-e61b-44d9-88ed-5944d1962f5e`

2. **Test refresh with captured refresh token** ✓
   - Refresh tokens DO survive across account logins
   - New refresh token issued with each refresh

### Phase 2: Implement Based on Findings

**If refresh tokens ARE invalidated on new login**:
- Implement Option B (Re-Capture workflow)
- Document the limitation clearly
- Consider prompting user automatically

**If refresh tokens survive**:
- Implement Option A (Token Refresh on Switch)
- This is the ideal solution

### Phase 3: Add Defensive Checks

Regardless of which option works:
- Add token verification before switch (Option D)
- Provide clear error messages
- Log switch attempts for debugging

---

## Research Tasks

### Task 1: Discover Token Refresh Mechanism

```bash
# Option 1: Check Claude Code network traffic
# Run Claude with debug logging
ANTHROPIC_LOG=debug claude

# Option 2: Search Claude Code source (if available)
# Look for OAuth/token refresh code

# Option 3: Check common OAuth endpoints
curl -s -X POST "https://console.anthropic.com/api/auth/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token&refresh_token=sk-ant-ort01-..."
```

### Task 2: Verify Refresh Token Persistence

```bash
# Sequence to test:
# 1. Log in as Account A, capture refresh token R_A
# 2. Log in as Account B
# 3. Try to use R_A to get a new access token
# 4. If it works, refresh tokens survive!
```

### Task 3: Identify Token Verification Endpoint

```bash
# Test lightweight auth check endpoints
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api.anthropic.com/v1/messages" \
  -d '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'

# Or a user profile endpoint if one exists
```

---

## Implementation Tasks

### Phase 1: Research (Before Coding) - COMPLETE

- [x] Test if refresh tokens survive across account logins
- [x] Discover the token refresh endpoint
- [x] Verify what HTTP status indicates invalid/revoked tokens
- [x] Document findings

### Phase 2: Add Token Verification - COMPLETE

- [x] Add `verify_access_token()` function to `claude-account`
- [x] Call verification before switch to fail fast
- [x] Provide clear error message if token is invalid

### Phase 3: Implement Token Refresh - COMPLETE

- [x] Add `refresh_oauth_token()` function
- [x] Integrate into `switch_account()` flow
- [x] Update both in-memory and stored credentials after refresh
- [x] Handle refresh failures gracefully

### Phase 4: Update Automatic Switch Hook

- [ ] Update `plan-limit-account-switch.sh` to use new switch mechanism
- [ ] Add token verification before auto-switch
- [ ] Handle case where no valid accounts available

---

## Files to Modify

| File | Changes |
|------|---------|
| `scripts/claude-account` | Add token verification, token refresh, improve switch flow |
| `hooks/plan-limit-account-switch.sh` | Use updated switch mechanism |

---

## Verification Checklist

After implementing, test:

1. **Token Refresh Test**
   - Capture Account A
   - Log in to Account B
   - Try to refresh Account A's token using refresh token
   - Document if it works or fails

2. **Manual Switch Test**
   - Capture both accounts
   - `claude-account switch` to other account
   - Run `claude` - verify it works

3. **Auto-Switch Test**
   - Hit rate limit
   - Verify automatic switch triggers
   - Verify new account works

4. **Session Resume Test**
   - Switch accounts
   - Use `--resume` with old session
   - Verify graceful handling

---

## Notes

### Why Session State Clearing is WRONG

Earlier analysis suggested clearing session state. This is **incorrect** because:
1. Normal login PRESERVES session state (verified from sample data)
2. Org-keyed caches remain with old org IDs even after login
3. The issue is token validity, not session/cache staleness

### Token Format

Tokens are opaque Anthropic format (`sk-ant-oat01-...`, `sk-ant-ort01-...`), NOT JWTs.
We cannot decode them - must rely on OAuth refresh flow for new tokens.

