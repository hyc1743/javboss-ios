package com.javboss.phone.data.api

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerOriginTest {
    @Test
    fun `accepts only the configured origin`() {
        val server = "http://192.168.1.10:8655"

        assertTrue(ServerOrigin.matches(server, "http://192.168.1.10:8655/videos/1/stream"))
        assertFalse(ServerOrigin.matches(server, "https://192.168.1.10:8655/videos/1/stream"))
        assertFalse(ServerOrigin.matches(server, "http://192.168.1.10:8080/videos/1/stream"))
        assertFalse(ServerOrigin.matches(server, "http://example.com/videos/1/stream"))
    }
}
