# baki-notify

Self-hosted push server for the Baki app. iOS only runs background refreshes when it feels like
it (sometimes hours apart). With this running, the server checks Bakaláři every couple of minutes
and sends a real push to the Baki app for new marks, Komens messages, noticeboard posts and
timetable changes. No third-party service is involved besides Apple's own push service.

Because pushes must be signed with a key from the Apple Developer account that owns the app, you
need to build and install Baki under your own account (the app's bundle ID and App Group already
have to be changed for that). One account and one server can cover your whole family or class.

## 1. Apple side (once)

Requires a paid Apple Developer Program membership; free personal teams can't use push.

1. In Xcode, select the Baki iOS target → Signing & Capabilities → add **Push Notifications**
   (this adds the `aps-environment` entitlement to `Baki iOS.entitlements`).
2. On developer.apple.com → Certificates, Identifiers & Profiles → Keys, create a key with
   **Apple Push Notifications service (APNs)** enabled. Download the `AuthKey_XXXXXXXXXX.p8`
   (you can only download it once) and note the Key ID and your Team ID.

## 2. Server

1. Make a `data/` folder next to `docker-compose.yml`. Put the `.p8` file in it and copy
   `config.example.json` to `data/config.json`. Fill in `key_id`, `team_id`, `key_file`,
   your app's `bundle_id`, and a long random `api_key` (`openssl rand -hex 24`).
2. `docker compose up -d --build`
3. Put it behind HTTPS (the app sends the Bakaláři password to it) and note the public URL.
   Without Docker: `go build -o baki-notify . && ./baki-notify data/config.json` (Go 1.22+).

## 3. App

Settings → **Push server**: enter the server URL, the API key and your Bakaláři password
(the app doesn't keep it), then tap Connect. The categories you enabled under Notifications
decide what you get. From then on the app stops polling by itself and relies on the server.

## Notes

- The first poll for a new account stores what already exists and sends nothing.
- The server stores each account's Bakaláři login in `data/registrations.json` (mode 0600).
  Only host it for people you trust, and protect `data/`.
- Phones whose token Apple reports as invalid are removed automatically; signing out in the app
  unregisters the device.
- Unofficial; unaffiliated with Bakaláři software s.r.o. Keep `poll_seconds` at 2 minutes or more.
