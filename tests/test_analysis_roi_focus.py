import unittest

from engine.python.basketball_engine.adapters.analysis import focus_roi_on_net


class FocusRoiOnNetTest(unittest.TestCase):
    def test_wide_roi_uses_calibrated_net_for_detection(self):
        roi = [43, 100, 876, 484]
        net = [381, 215, 434, 265]

        focused = focus_roi_on_net(roi, net)

        self.assertEqual(focused, [275, 115, 540, 365])
        self.assertLess(focused[0], 405)
        self.assertGreater(focused[2], 405)
        self.assertLess(focused[2], 615)

    def test_invalid_or_outside_net_keeps_original_roi(self):
        roi = [100, 100, 300, 300]

        self.assertEqual(focus_roi_on_net(roi, None), roi)
        self.assertEqual(focus_roi_on_net(roi, [400, 100, 450, 150]), roi)

    def test_existing_tight_roi_is_preserved(self):
        roi = [280, 120, 520, 360]

        self.assertEqual(focus_roi_on_net(roi, [381, 215, 434, 265]), roi)


if __name__ == "__main__":
    unittest.main()
