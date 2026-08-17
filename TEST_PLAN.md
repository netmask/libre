# Libre Glucose Menu Bar App — Test Plan & Architecture

## Architecture Overview

The app consists of these main components:

1. **LibreLinkAPI** — Handles authentication and API calls to LibreLink Up
2. **GlucoseService** — Manages glucose data fetching, caching, and refresh
3. **MenuBarView** — SwiftUI MenuBarExtra displaying current glucose
4. **SettingsView** — User preferences (credentials, refresh interval)

## Data Models

- **GlucoseReading**: Current glucose value, trend, timestamp
- **TrendArrow**: Enum for glucose trend direction
- **ConnectionStatus**: API connection state
- Credentials and session tokens are stored securely in the Keychain

## Test Plan

### 1. LibreLinkAPI Tests (Unit Tests)

#### Authentication Tests
- Login with valid credentials returns auth token
- Login with invalid credentials throws auth error
- Login with network error throws network error
- Token refresh when expired refreshes automatically
- Region redirect during login retries against the new region

#### API Request Tests
- Fetch connections returns patient list
- Fetch glucose data returns latest reading
- Fetch glucose data with expired token refreshes and retries
- Fetch glucose data parses all trend arrows

#### Error Handling Tests
- Rate limited responses return the appropriate error
- Server errors return the appropriate error
- Invalid responses throw a decoding error

### 2. GlucoseService Tests (Unit Tests)

#### Data Fetching Tests
- Start monitoring fetches data immediately
- Start monitoring schedules periodic refresh
- Stop monitoring cancels scheduled refresh
- Refresh updates published values

#### Caching Tests
- Cached reading returned when offline
- Cached reading cleared on logout

#### State Management Tests
- Connection status updates on success
- Connection status updates on failure
- Last updated timestamp updates after fetch

### 3. UI Tests (SwiftUI Preview Tests + UI Tests)

#### MenuBarView Tests
- Menu bar label displays glucose value and trend arrow
- Menu bar label shows loading and error states
- Menu content shows last-updated time, refresh, settings, and quit

#### SettingsView Tests
- Shows email/password fields and refresh interval picker
- Saves credentials to the keychain; loads existing credentials

### 4. Integration Tests

- End to end: login and fetch glucose
- End to end: refresh cycle
- End to end: handle network disconnect

## Mock Objects

1. **MockURLSession** — Simulates network responses
2. **MockKeychainService** — In-memory keychain for tests

## LibreLink Up API Reference (Unofficial)

Base URL: `https://api.libreview.io` (varies by region)

Endpoints:
- `POST /llu/auth/login` — Authenticate user
- `GET /llu/connections` — Get linked patients
- `GET /llu/connections/{patientId}/graph` — Get glucose data

Headers:
- `Content-Type: application/json`
- `product: llu.android`
- `version: 4.16.0`
- `Authorization: Bearer {token}` (after login)
