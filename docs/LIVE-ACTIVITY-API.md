# Live Activity over push — requirements for the backend

What the server has to implement to drive an iOS Live Activity, and one thing that has to
change in the app first.

---

## Status: not built, deliberately

**Decided 2026-08-28: halted, not abandoned.** This document is the deliverable rather
than a to-do list.

Three reasons, in order of weight:

1. **The endpoints alone would do nothing.** See the next section — with the widget as it
   stands, a push-driven update cannot change the card. The real prerequisite is replacing
   `live_activities` with a hand-written ActivityKit bridge, and that is the larger half of
   the work.
2. **It cannot be verified.** Live Activity push does not work on the simulator, and there
   is no physical iPhone. This project's rule is not to call iOS verified without evidence
   (`docs/screenshots/`), so building it now would produce code nobody could prove either
   way — the exact thing the rest of these docs avoid.
3. **The local-driven Live Activity already works** and is screenshotted. Push-driven adds
   one capability: the *server* moving the card. Everything else is demonstrated.

What is already in place, should this be picked up: the app sends both tokens
(`live_activity_service.dart`), and the Go backend already has
`fcm.Message.LiveActivityToken` and `store.KindLiveActivity`. Only the four routes below
are missing, which is why the app logs `404`.

The backend is **still deployed** — do not re-provision it.

---

## Why the naive version fails

**With the widget as it stands today, a push-driven update cannot change anything on
screen.** Not "unreliably" — it cannot. The endpoints would return 200, FCM would accept
the message, APNs would deliver it, and the card would sit there unchanged.

The reason is the plugin's data model, described in `DECISIONS.md`. `ContentState` carries
exactly one field:

```swift
public struct ContentState: Codable, Hashable {
  var appGroupId: String?
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicCodingKeys.self)
    appGroupId = try container.decodeIfPresent(String.self, forKey: DynamicCodingKeys("appGroupId"))
  }
}
```

Everything the widget draws — `orderId`, `stage`, `eta`, `rider` — is read out of the
shared App Group's `UserDefaults`, and those values are written by
`LiveActivitiesPlugin.updateActivity` **in the app process**:

```swift
for (key, value) in data { sharedDefault.set(value, forKey: "\(prefix)_\(key)") }
await activity.update(using: LiveDeliveryData(appGroupId: appGroupId))
```

A Live Activity push does not wake the app. So there is no process to write those keys,
`ContentState.init(from:)` discards every key it does not recognise, and the widget
re-renders from unchanged storage.

### What has to change first

Move the drawn fields out of the App Group and into a typed `ContentState`:

```swift
struct DeliveryAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    var stage: Int
    var eta: String
    var rider: String
  }
  var orderId: String          // fixed for the life of the activity
}
```

That means **dropping `live_activities` and writing the ActivityKit bridge directly** — it
is the plugin's fixed `LiveActivitiesAppAttributes` that forces the App Group detour, and
it cannot be configured away. Roughly: a MethodChannel mirroring `LiveUpdateService`'s
shape (`start` / `update` / `end` / `capabilities`), plus `Activity.request`,
`activity.update`, `activity.end`, and the two token streams.

The local-only demo already works without any of this, so the change buys exactly one
thing: the server being able to drive the card. Decide whether that is worth it before
building the endpoints, because the endpoints are useless without it.

`content-state` in the push must then decode into that struct **field for field**. A
mismatch is silent: APNs accepts the push and ActivityKit drops it.

---

## What the app already sends

Implemented today in `lib/services/live_activity_service.dart`, fired from
`activityUpdateStream` and `pushToStartTokenUpdateStream`:

```
POST /api/live-activity/token
X-Demo-Key: <key>

{ "kind": "activity" | "push-to-start",
  "token": "<hex>",
  "activityId": "<uuid or null>" }
```

Both kinds arrive on the same endpoint with a discriminator, because what the server does
with them differs completely. Expected response: `200`. It currently returns `404`, which
the app logs as `[live] activity token FAILED - 404` and otherwise ignores.

**Note the app does not send its FCM registration token here** — the server must join on
whatever it already stored via `POST /api/tokens`. The Live Activity message needs *both*:
`message.token` is the FCM registration token, `apns.live_activity_token` is the activity
one.

---

## Endpoints to add

| | Purpose | Token used |
|---|---|---|
| `POST /api/live-activity/token` | store either token | — |
| `POST /api/live-activity/start` | create an activity remotely | push-to-start |
| `POST /api/live-activity/update` | advance a running one | activity |
| `POST /api/live-activity/end` | dismiss it | activity |

Keep the three token maps separate, as plan v2 §5 says — `fcmTokens`,
`liveActivityTokens`, `pushToStartTokens`. They have different scopes and different
lifetimes and conflating them produces sends to dead tokens.

| Token | Scope | Lifetime |
|---|---|---|
| FCM registration | the app install | stable, refreshable |
| Live Activity push | **one activity** | dies when that activity ends |
| push-to-start | the activity *type* | stable; iOS 17.2+ only |

**Delete the activity token the moment the activity ends.** Keeping it guarantees a later
send fails with a token error pointing nowhere near the cause.

---

## Message shape

The Go Admin SDK has no `live_activity_token` field on `ApnsConfig`, so these must go out
as raw HTTP v1 — which is what the whole backend already does (`DECISIONS.md`). Same
`POST https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send`, same OAuth
scope.

```jsonc
{
  "message": {
    "token": "<FCM registration token>",
    "apns": {
      "live_activity_token": "<activity or push-to-start token>",
      "headers": {
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "apns-topic": "com.f0h.flt-noti-demo.push-type.liveactivity"
      },
      "payload": {
        "aps": {
          "timestamp": 1787856605,          // epoch SECONDS, not millis
          "event": "update",                // "start" | "update" | "end"
          "content-state": { "stage": 2, "eta": "12 min", "rider": "Aoy · Honda Wave" }
        }
      }
    }
  }
}
```

`start` additionally needs `attributes-type` and `attributes`, and uses the push-to-start
token:

```jsonc
"aps": {
  "timestamp": 1787856605,
  "event": "start",
  "attributes-type": "DeliveryAttributes",
  "attributes": { "orderId": "MAC-1" },
  "content-state": { "stage": 0, "eta": "25 min", "rider": "Aoy · Honda Wave" },
  "alert": { "title": "Order received", "body": "We are getting started" }
}
```

Points that bite:

- **`apns-topic` is the bundle ID with `.push-type.liveactivity` appended.** Not the plain
  bundle ID.
- **`attributes-type` must equal the Swift struct's name**, and `attributes` must decode
  into it. Both are silent failures.
- **`timestamp` is seconds.** Milliseconds are accepted and the update is ignored as stale.
- Sandbox vs production applies exactly as it does to ordinary push — see `SETUP.md` §D.4.
- iOS throttles Live Activity pushes. A 4-step run at 20 s intervals is comfortably
  inside the budget; much faster is not, and `NSSupportsLiveActivitiesFrequentUpdates` is
  already set in `Info.plist`.

The header and `aps` key names above follow plan v2 §5.1 and Apple's ActivityKit push
documentation. **None of it has been sent for real yet** — nothing in this file is
verified, unlike the rest of `TESTING.md`.

---

## Testing

**A physical iPhone, throughout.** Not a preference:

- Live Activity update over push does not work on the simulator (`TESTING.md`).
- The simulator refuses every `content-available` push outright, which rules out the
  `delivery_step` path that would drive the same sequence.

The sane order is the one in `SETUP.md` §D.4 — prove device→APNs, then backend→FCM auth,
then the real send — because a Live Activity push that silently does nothing has at least
four plausible causes and no error message.

---

## Also missing, for the Phase 6 finale

`/api/simulate/delivery` already sends `delivery_step` data messages and they arrive
(verified 2026-08-28: four of them, 20.3 s apart). On Android
`DeliveryMessagingService.kt` turns those into Live Update calls natively. **There is no
iOS equivalent** — `push_service.dart` only logs them.

So the finale has two possible shapes on iOS, and they are different pieces of work:

1. Server drives the Live Activity directly with `live-activity/update` pushes — needs
   everything above.
2. Server keeps sending `delivery_step`, and iOS handles it natively like Android does —
   needs a Notification Service Extension or equivalent, and still cannot work while the
   app is killed the way ActivityKit push can.

(1) is the one plan v2 describes and the one worth having.
