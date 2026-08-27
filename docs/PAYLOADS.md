# Payloads & delivery behaviour

The payloads the server actually sends, and what each one does on a real device.
Everything here was measured on a Galaxy S21 (Android 15 / API 35) against the deployed
backend — not inferred.

Payloads are logged verbatim by the backend (`internal/router` → `logPayload`), so what
is printed below is byte-for-byte what went to `fcm.googleapis.com`.

---

## The delivery matrix

The result that matters: **how the app is killed changes whether the message arrives at
all**, and it is not the distinction most people expect.

| App state | Notification message | Data-only message |
|---|---|---|
| Foreground | ✅ delivered — `onMessage` | ✅ delivered — app draws it |
| Background (process alive) | ✅ shown by the OS | ✅ background isolate draws it |
| Process killed (swiped away) | ✅ shown by the OS | ✅ **FCM revives the process** |
| **Force-stopped** | ❌ **not delivered** | ❌ **not delivered** |
| After manual relaunch | ✅ | ✅ |

### Force-stop is the one that actually breaks things

Both sends still return HTTP 200 — FCM accepts the message. It is simply never delivered,
and the process is never revived. Android puts a force-stopped app into a **stopped
state** in which it receives no broadcasts at all, FCM included, until the user launches
it by hand.

This is what OEM "battery optimisation" and aggressive task-killers do on Xiaomi, Oppo,
Vivo and Samsung devices, and it is why a push pipeline that works perfectly in
development quietly loses messages in the field. **A 200 from FCM is not proof of
delivery.**

Note that swiping the app away from recents is *not* the same thing: the process dies,
but the app is not stopped, so FCM still wakes it. Only an explicit Force stop — from
Settings, or from an OEM cleaner — triggers the stopped state.

None of this can be observed on an emulator.

---

## Notification message

The OS renders it; the app is never consulted.

```json
{
  "message": {
    "token": "<device token>",
    "notification": { "title": "Hello from the server", "body": "..." },
    "android": { "priority": "high" },
    "apns": {
      "headers": { "apns-priority": "10", "apns-push-type": "alert" },
      "payload": { "aps": { "alert": { "title": "...", "body": "..." }, "sound": "default" } }
    }
  }
}
```

**Trade-off:** survives the process being dead, needs no app code — but you cannot
control the appearance, and on Android a tap opens the launcher activity rather than
routing anywhere useful.

---

## Data-only message

Nothing is displayed until the app draws it.

```json
{
  "message": {
    "token": "<device token>",
    "data": { "title": "...", "body": "...", "type": "..." },
    "android": { "priority": "high" },
    "apns": {
      "headers": { "apns-priority": "5", "apns-push-type": "background" },
      "payload": { "aps": { "content-available": 1 } }
    }
  }
}
```

Two things here are mandatory, not stylistic:

- **`android.priority: "high"`** — at normal priority Doze holds data-only messages until
  the next maintenance window, which can be many minutes.
- **`aps.content-available: 1` with no `alert`, `sound` or `badge`** — add any of those
  and iOS treats it as a normal alert and never wakes the app silently.

**Trade-off:** total control over presentation, at the cost of needing the process to be
alive-or-revivable. It is the row that goes wrong under force-stop.

### It needs a background handler, or it silently does nothing

Handling data-only in `onMessage` alone only covers the foreground. Backgrounded, the
message is delivered to a **separate isolate** that shares no state with the app, so the
plugin has to be initialised again in there before anything can be drawn. During testing
this exact gap made backgrounded data-only pushes vanish — delivered, logged, invisible.

---

## Topic broadcast

Targets a subscription rather than a token:

```json
{
  "message": {
    "topic": "demo-all",
    "notification": { "title": "...", "body": "..." },
    "android": { "priority": "high" },
    "apns": { "headers": { "apns-priority": "10", "apns-push-type": "alert" }, "payload": { "aps": {...} } }
  }
}
```

The response carries a message name with no device in it —
`projects/<project>/messages/6761983765843508898` — because fan-out happens on Google's
side. There is no per-device delivery result to inspect.

---

## Reading the response

A successful send returns the message name:

```
projects/sample-noti-719f8/messages/0:1787813323203488%0271be0a0271be0a
```

Worth doing once: fire a push with the app foregrounded and compare that id to the one
the device logs on arrival. They match, which is the only way to prove a specific message
made the round trip rather than assuming it from a 200.

### Errors worth recognising

| Error | Cause |
|---|---|
| `SENDER_ID_MISMATCH` | token was issued by a different Firebase project than the one sending |
| `UNREGISTERED` | app uninstalled, or the token rotated — delete it from the store |
| `INVALID_ARGUMENT` | malformed token |
| `SERVICE_DISABLED` | `fcm.googleapis.com` not enabled on the project |
| `Permission 'cloudmessaging.messages.create' denied` | service account has the legacy `firebasenotifications.admin` instead of `firebasecloudmessaging.admin` |
| silent 400 on iOS | APNs sandbox token sent to production, or the reverse |

The last three all look like a bad key and are not.
