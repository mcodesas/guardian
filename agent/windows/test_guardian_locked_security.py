import unittest
from guardian_locked_security import (
    parse_windows_event, relevant_failed_unlock, valid_location, WindowsEventReader,
)

NAMESPACE = 'http://schemas.microsoft.com/win/2004/08/events/event'


def xml(kind, seq, logon_type=None):
    data = '' if logon_type is None else '<EventData><Data Name="LogonType">%s</Data></EventData>' % logon_type
    return ('<Event xmlns="%s"><System><EventID>%d</EventID>'
            '<EventRecordID>%d</EventRecordID><TimeCreated SystemTime="2026-11-23T10:00:00Z"/>'
            '</System>%s</Event>') % (NAMESPACE, kind, seq, data)


class TestLockedSecurity(unittest.TestCase):
    def test_events_are_parsed_without_credentials(self):
        info = parse_windows_event(xml(4625, 42, '7'))
        self.assertEqual(info['eventId'], 4625)
        self.assertEqual(info['recordId'], 42)
        self.assertEqual(info['logonType'], '7')
        self.assertNotIn('password', info)

    def test_windows_unlock_failures_require_correct_context(self):
        self.assertTrue(relevant_failed_unlock({'eventId': 4625, 'logonType': '7'}, False))
        self.assertTrue(relevant_failed_unlock({'eventId': 4625, 'logonType': '2'}, True))
        self.assertFalse(relevant_failed_unlock({'eventId': 4625, 'logonType': '3'}, True))
        self.assertFalse(relevant_failed_unlock({'eventId': 4625, 'logonType': '2'}, False))

    def test_location_validation(self):
        self.assertTrue(valid_location({'latitude':4.57,'longitude':-74.2,'accuracyMeters':60}))
        self.assertFalse(valid_location({'latitude':95,'longitude':-74.2,'accuracyMeters':60}))
        self.assertFalse(valid_location({'latitude':float('nan'),'longitude':-74.2,'accuracyMeters':60}))

    def test_baseline_does_not_resend_old_events(self):
        events = [parse_windows_event(xml(4800, 1)),parse_windows_event(xml(4625, 2,'7'))]
        monitor = WindowsEventReader()
        monitor._read = lambda: events
        self.assertEqual(monitor.poll(), [])
        self.assertTrue(monitor.locked)
        events.append(parse_windows_event(xml(4625, 3,'7')))
        self.assertEqual(len(monitor.poll()), 1)
        self.assertEqual(monitor.poll(), [])

    def test_successful_unlock_clears_lock_state(self):
        events = [parse_windows_event(xml(4800, 1))]
        monitor = WindowsEventReader()
        monitor._read = lambda: events
        monitor.poll()
        events.append(parse_windows_event(xml(4801, 2)))
        events.append(parse_windows_event(xml(4625, 3,'2')))
        self.assertEqual(monitor.poll(), [])
        self.assertFalse(monitor.locked)


if __name__ == '__main__':
    unittest.main()
