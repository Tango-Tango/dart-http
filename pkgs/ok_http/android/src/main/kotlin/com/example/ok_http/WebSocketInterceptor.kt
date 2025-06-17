// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

package com.example.ok_http

import okhttp3.Interceptor
import okhttp3.OkHttpClient

/**
 * Usage of `chain.proceed(...)` via JNI Bindings leads to threading issues. This is a workaround
 * to intercept the response before it is parsed by the WebSocketReader, to prevent response parsing errors.
 *
 * https://github.com/dart-lang/native/issues/1337
 */
class WebSocketInterceptor {
    companion object {
        fun addWSInterceptor(
            clientBuilder: OkHttpClient.Builder
        ): OkHttpClient.Builder {
            return clientBuilder.addInterceptor(Interceptor { chain ->
                val request = chain.request()
                val response = chain.proceed(request)

                // Grab the original extensions header
                val originalHeader = response.header("sec-websocket-extensions")

                // Removing this header to ensure that OkHttp does not fail due to unexpected values
                val builder = response.newBuilder()
                    .removeHeader("sec-websocket-extensions")

                // Only re-add if the original response contained "permessage-deflate"
                if (originalHeader?.contains("permessage-deflate") == true) {
                    builder.addHeader("sec-websocket-extensions", "permessage-deflate")
                }

                builder.build()
            })
        }
    }
}
