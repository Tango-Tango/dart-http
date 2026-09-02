# OkHttp JNI lifetime soak

Compares two **release AOT** example APKs that repeatedly call `OkHttpClient`
the same way Tango Tango does (60s connect/read/write timeouts). Each request
hits `writeTimeout` and `headers().toMultimap()`.

JNI is not modified. Overnight on a plugged-in retail device is the intended
validation.

| Label | SHA |
| --- | --- |
| old | `74e326d6fec11b579020b19bff844a728951fa5b` |
| guarded | `ce1f7251873a2f50c2c7f995d42ee904e6bff93b` |

The runner leaves Flutter's release minifier on and applies the same keep
rules Shine uses (`okhttp3.**`, `okio.**`, `com.example.ok_http.**`).

## Build both APKs

```sh
pkgs/ok_http/tool/run_jni_lifetime_soak.sh build
```

APKs land in `/tmp/okhttp-soak-artifacts/{old,guarded}/app-release.apk`.

Override the target with `SOAK_URL` / `SOAK_WORKERS` if needed.

## Run overnight

Plug the device in, leave this app in the foreground, USB debugging on:

```sh
pkgs/ok_http/tool/run_jni_lifetime_soak.sh run old 8
pkgs/ok_http/tool/run_jni_lifetime_soak.sh run guarded 8
```

The runner enables stay-awake, installs the APK, starts soak, and collects
logcat plus DropBox native crashes if the process dies.

Manual collect:

```sh
pkgs/ok_http/tool/run_jni_lifetime_soak.sh collect
```

## Pass / fail

The comparison is only valid if **old dies** and **guarded survives** the same
workload.

- Old is a hit if logcat/DropBox shows `libdartjni.so` with
  `OkHttpClient$Builder.writeTimeout` or `Headers.toMultimap`.
- Guarded passes that run if the process stays up and `SOAK label=guarded`
  counters keep increasing.
- If old never crashes, the run is **inconclusive**. Repeat overnight or
  raise `SOAK_WORKERS`.

Do not treat a quiet guarded run as proof unless old reproduced the stack.
