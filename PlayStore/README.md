# Google Play — app signing certificates

Public certificates downloaded from Play Console (Play App Signing, quantum-ready hybrid). These are **not** private keys and cannot sign an AAB/APK.

## Files (`certificates/`)

| File | Role |
|------|------|
| `deployment_cert.der` | Classical app-signing cert for devices **before Android 17** |
| `hybrid_classical_cert.der` | Classical half of the hybrid signature (Android 17+) |
| `hybrid_pqc_cert.der` | Post-quantum (ML-DSA) half of the hybrid signature (Android 17+) |

Issued by Google Inc. / Android · valid **2026-07-31 → 2056-07-31**.

## Fingerprints (register all three with APIs / App Links)

### Deployment (pre–Android 17)

- **SHA-1:** `D0:C9:52:22:62:D8:D2:B3:32:3C:68:E5:23:27:AD:BF:BD:05:A5:E5`
- **SHA-256:** `B4:28:D8:22:00:88:94:6C:64:02:74:91:03:2B:B8:9F:89:F7:F5:1A:D9:C5:02:4D:BD:D8:21:2E:96:51:85:83`

### Hybrid classical (Android 17+)

- **SHA-1:** `5A:C4:02:C8:3C:E3:E5:EC:0E:6B:67:29:09:E8:78:7A:7F:67:0C:45`
- **SHA-256:** `2B:2F:8A:7F:66:4D:44:87:EF:C2:3B:0D:3B:21:CE:FA:A2:7C:FA:40:E9:52:CC:1A:CA:E3:B5:58:B4:AE:CF:C5`

### Hybrid PQC (Android 17+)

- **SHA-1:** `20:13:1C:DB:DA:3E:89:79:81:48:12:91:8B:AB:2B:0E:55:02:27:7A`
- **SHA-256:** `8D:BC:E4:03:B9:3C:85:F0:47:4F:BB:55:C1:B9:86:6E:0D:9F:1A:E9:73:D9:98:80:6A:FE:89:15:29:BE:E2:84`

Use these SHA-256 values in `assetlinks.json` for Android App Links (TWA package id is currently `com.openthanks.myapp`), and all SHA-1/SHA-256 values in Firebase / Google Cloud OAuth client config.

TWA project (Bubblewrap source, no private keystore): https://github.com/FlaviuSim/openthanks-twa

## Still needed (not in this zip)

1. **Upload keystore** (private `.jks` / `.keystore`) — you create and keep this; sign every AAB you upload to Play. Google never gives you this private key.
2. **Upload certificate** (`upload_cert.der`) — public cert for that upload key; download from the same Play App Signing page after the first upload / upload-key registration. Also add its fingerprints for debug/local API testing when installs come from your signed build rather than Play.

Do **not** commit the upload keystore or its passwords to git.
