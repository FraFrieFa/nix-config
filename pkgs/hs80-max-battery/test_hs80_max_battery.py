import unittest
from unittest import mock

import hs80_max_battery as hs80


class DecodeTests(unittest.TestCase):
    def test_v2_battery_request(self):
        request = hs80.v2_request(0x09, 0x0F)
        self.assertEqual(len(request), 65)
        self.assertEqual(request[:5], bytes([0x00, 0x02, 0x09, 0x02, 0x0F]))
        self.assertEqual(request[5:], bytes(60))

    def test_flush_is_bounded_for_noisy_device(self):
        with mock.patch.object(hs80, "read_report", return_value=b"noise") as read:
            self.assertEqual(hs80.flush_reports(1, max_reports=7, max_seconds=10), 7)
        self.assertEqual(read.call_count, 7)



if __name__ == "__main__":
    unittest.main()
