import asyncio
import unittest

from app.body_limit import RequestBodyLimitMiddleware


class BodyLimitMiddlewareTest(unittest.TestCase):
    def test_rejects_streamed_body_without_content_length(self):
        messages = []

        async def downstream(scope, receive, send):
            await receive()

        async def receive():
            return {"type": "http.request", "body": b"x" * 1025, "more_body": False}

        async def send(message):
            messages.append(message)

        middleware = RequestBodyLimitMiddleware(downstream, 1024)
        asyncio.run(middleware({"type": "http", "method": "POST", "headers": []}, receive, send))
        self.assertEqual(413, messages[0]["status"])

    def test_rejects_unsafe_limit_configuration(self):
        with self.assertRaises(ValueError):
            RequestBodyLimitMiddleware(None, 1023)
        with self.assertRaises(ValueError):
            RequestBodyLimitMiddleware(None, 10 * 1024 * 1024 + 1)


if __name__ == "__main__":
    unittest.main()
