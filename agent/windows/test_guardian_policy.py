import unittest

from guardian_policy import (
    is_valid_trust_window,
    should_flag_unknown,
    should_lock_on_away,
    should_request_remote_approval,
)


class GuardianPolicyTests(unittest.TestCase):
    def test_unknown_face_is_never_bypassed_by_previous_approval(self):
        self.assertTrue(should_flag_unknown(
            consecutive=8, idle_seconds=2, now=100, cooldown_until=0))
        self.assertFalse(should_flag_unknown(
            consecutive=7, idle_seconds=2, now=100, cooldown_until=0))
        self.assertFalse(should_flag_unknown(
            consecutive=8, idle_seconds=30, now=100, cooldown_until=0))

    def test_absence_lock_ignores_previous_mobile_trust(self):
        self.assertTrue(should_lock_on_away(
            absence_seconds=20, idle_seconds=20, timeout_seconds=15,
            enabled=True, now=100, cooldown_until=0))
        self.assertFalse(should_lock_on_away(
            absence_seconds=20, idle_seconds=20, timeout_seconds=15,
            enabled=False, now=100, cooldown_until=0))
        self.assertFalse(should_lock_on_away(
            absence_seconds=10, idle_seconds=20, timeout_seconds=15,
            enabled=True, now=100, cooldown_until=0))

    def test_mobile_approval_only_for_active_unverifiable_session(self):
        base = dict(absence_seconds=20, idle_seconds=0,
                    timeout_seconds=15, now=100, cooldown_until=0)
        self.assertTrue(should_request_remote_approval(
            **base, trust_until=0))
        self.assertFalse(should_request_remote_approval(
            **base, trust_until=120))
        self.assertFalse(should_request_remote_approval(
            absence_seconds=20, idle_seconds=25, timeout_seconds=15,
            now=100, cooldown_until=0, trust_until=0))

    def test_expired_trust_window(self):
        self.assertTrue(is_valid_trust_window(until=200, now=199))
        self.assertFalse(is_valid_trust_window(until=200, now=200))


if __name__ == "__main__":
    unittest.main()
