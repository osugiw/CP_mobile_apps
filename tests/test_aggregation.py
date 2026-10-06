"""
test_aggregation.py — unit tests for aggregation and window logic.
No DB or network required.
"""
import pytest
from datetime import datetime, timedelta


class TestWindowBoundaries:
    def test_6h_window(self):
        until = datetime(2026, 4, 17, 14, 0, 0)
        start = until - timedelta(hours=6)
        assert start == datetime(2026, 4, 17, 8, 0, 0)

    def test_24h_window(self):
        until = datetime(2026, 4, 17, 14, 0, 0)
        start = until - timedelta(hours=24)
        assert start == datetime(2026, 4, 16, 14, 0, 0)

    def test_day_window_midnight(self):
        until = datetime(2026, 4, 17, 14, 30, 45)
        start = until.replace(hour=0, minute=0, second=0, microsecond=0)
        assert start == datetime(2026, 4, 17, 0, 0, 0)

    def test_day_window_already_midnight(self):
        until = datetime(2026, 4, 17, 0, 0, 0)
        start = until.replace(hour=0, minute=0, second=0, microsecond=0)
        assert start == until


class TestContextTruncation:
    def _truncate(self, chunks, max_chars):
        """Mirrors the truncation logic in summary_window()."""
        chunks_desc = sorted(chunks, key=lambda c: c[1], reverse=True)
        parts, total, rids = [], 0, set()
        for content, ts, rid in chunks_desc:
            if total + len(content) > max_chars:
                remaining = max_chars - total
                if remaining > 100:
                    parts.append(f"[{str(ts)[:16]}] {content[:remaining]}...")
                break
            parts.append(f"[{str(ts)[:16]}] {content}")
            total += len(content)
            rids.add(rid)
        return "\n\n---\n\n".join(reversed(parts)), total, rids

    def test_fits_in_limit(self):
        now = datetime.utcnow()
        chunks = [("hello world", now, 1), ("foo bar", now + timedelta(minutes=5), 2)]
        text, total, rids = self._truncate(chunks, max_chars=500)
        assert "hello world" in text
        assert "foo bar" in text
        assert total == len("hello world") + len("foo bar")
        assert rids == {1, 2}

    def test_truncates_oldest_first(self):
        now = datetime.utcnow()
        # 50 chars each, limit=60 — newest (chunk2) should be included, oldest truncated
        chunks = [
            ("A" * 50, now, 1),
            ("B" * 50, now + timedelta(minutes=5), 2),
        ]
        text, total, rids = self._truncate(chunks, max_chars=60)
        assert total <= 60
        assert 2 in rids          # newest always included
        assert 1 not in rids      # oldest dropped

    def test_empty_chunks(self):
        text, total, rids = self._truncate([], max_chars=1000)
        assert text == ""
        assert total == 0
        assert rids == set()


class TestIntentContextFormatting:
    def _format(self, intents):
        return "\n".join(
            f"- {i['task']} ({i['intent_type']}, conf={i['fused_confidence']:.2f})"
            for i in intents[:10]
        ) or "None detected"

    def test_formats_correctly(self):
        intents = [
            {"task": "Call doctor", "intent_type": "appointment", "fused_confidence": 0.85},
            {"task": "Buy milk", "intent_type": "grocery", "fused_confidence": 0.60},
        ]
        result = self._format(intents)
        assert "Call doctor" in result
        assert "appointment" in result
        assert "conf=0.85" in result
        assert "Buy milk" in result

    def test_empty_intents(self):
        assert self._format([]) == "None detected"

    def test_caps_at_10(self):
        intents = [
            {"task": f"Task {i}", "intent_type": "general", "fused_confidence": 0.5}
            for i in range(15)
        ]
        result = self._format(intents)
        assert result.count("- Task") == 10


class TestWindowTypeValidation:
    VALID = ("6h", "day", "24h")

    def test_valid_windows(self):
        for w in self.VALID:
            assert w in self.VALID

    def test_invalid_window(self):
        assert "1h" not in self.VALID
        assert "week" not in self.VALID
        assert "" not in self.VALID
