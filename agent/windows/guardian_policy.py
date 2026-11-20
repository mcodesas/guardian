"""Pure decision predicates for Guardian's Windows evaluation agent.

No camera, biometric inference or OS-specific APIs: these rules can be
unit-tested on Linux in CI. The native agent remains the only component
that actually asks Windows to lock a session.
"""


def should_flag_unknown(*, consecutive: int, idle_seconds: float,
                        now: float, cooldown_until: float) -> bool:
    """A temporary remote approval must NEVER hide an unknown visible face."""
    return consecutive >= 8 and idle_seconds < 20 and now > cooldown_until


def should_lock_on_away(*, absence_seconds: float, idle_seconds: float,
                        timeout_seconds: int, enabled: bool,
                        now: float, cooldown_until: float) -> bool:
    """Away-lock remains in effect even during a temporary mobile approval."""
    return (enabled and 5 <= timeout_seconds <= 300
            and absence_seconds >= timeout_seconds
            and idle_seconds >= timeout_seconds
            and now > cooldown_until)


def should_request_remote_approval(*, absence_seconds: float,
                                   idle_seconds: float, timeout_seconds: int,
                                   trust_until: float, now: float,
                                   cooldown_until: float) -> bool:
    """Ask only if somebody uses an unverifiable session and trust expired."""
    return (5 <= timeout_seconds <= 300
            and absence_seconds >= timeout_seconds
            and idle_seconds < timeout_seconds
            and now >= trust_until
            and now > cooldown_until)


def is_valid_trust_window(*, until: float, now: float) -> bool:
    return until > now
