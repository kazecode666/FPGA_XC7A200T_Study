"""Focused tests for the independent Step 6C3 integer oracle."""

import unittest

from step6c3_svpwm_reference import (
    ONE_F32,
    dwell_from_ab,
    duty_from_sector,
    round_div_signed,
    round_shift_away,
    sector_xyz,
    svpwm_step,
)


class Step6C3ReferenceTests(unittest.TestCase):
    def test_zero_vector(self):
        r = svpwm_step(0, 0, 48 << 15)
        self.assertEqual(r["sector"], 2)
        self.assertEqual(r["t1"], 0)
        self.assertEqual(r["t2"], 0)
        self.assertEqual(
            (r["duty_u"], r["duty_v"], r["duty_w"]),
            (1 << 23, 1 << 23, 1 << 23),
        )

    def test_sector_equality_boundary(self):
        # 433*A - 250*B == 0; b1 deliberately includes equality.
        A, B = 25000, 43300
        r = sector_xyz(A, B)
        self.assertEqual(r["cmp1"], 0)
        self.assertEqual(r["b1"], 1)

    def test_cmp1_minus_zero_plus_one(self):
        cases = [
            (24903, 43132, -1, 0, 1),
            (25000, 43300, 0, 1, 3),
            (25097, 43468, 1, 1, 3),
        ]
        for A, B, expected_cmp1, expected_b1, expected_sector in cases:
            with self.subTest(cmp1=expected_cmp1):
                r = sector_xyz(A, B)
                self.assertEqual(r["cmp1"], expected_cmp1)
                self.assertEqual(r["b1"], expected_b1)
                self.assertEqual(r["sector"], expected_sector)

    def test_cmp2_minus_zero_plus_one(self):
        cases = [
            (-153, 265, -1, 0),
            (-250, 433, 0, 0),
            (-97, 168, 1, 1),
        ]
        for A, B, expected_cmp2, expected_b2 in cases:
            with self.subTest(cmp2=expected_cmp2):
                r = sector_xyz(A, B)
                self.assertEqual(r["cmp2"], expected_cmp2)
                self.assertEqual(r["b2"], expected_b2)

    def test_named_cmp1_plan_points_straddle_equality(self):
        self.assertEqual(sector_xyz(25000, 43299)["cmp1"], 250)
        self.assertEqual(sector_xyz(25000, 43300)["cmp1"], 0)
        self.assertEqual(sector_xyz(25000, 43301)["cmp1"], -250)

    def test_six_sector_interior_points(self):
        cases = [
            (0, 32768, 1),
            (32768, -32768, 2),
            (32768, 32768, 3),
            (-32768, -32768, 4),
            (-32768, 32768, 5),
            (0, -32768, 6),
        ]
        for A, B, expected_sector in cases:
            with self.subTest(sector=expected_sector):
                self.assertEqual(sector_xyz(A, B)["sector"], expected_sector)

    def test_round_shift_nearest_ties_away_signed(self):
        self.assertEqual(round_shift_away(1, 1), 1)
        self.assertEqual(round_shift_away(-1, 1), -1)
        self.assertEqual(round_shift_away(3, 1), 2)
        self.assertEqual(round_shift_away(-3, 1), -2)

    def test_round_div_nearest_ties_away_signed(self):
        self.assertEqual(round_div_signed(1, 2, frac_bits=0), 1)
        self.assertEqual(round_div_signed(-1, 2, frac_bits=0), -1)
        self.assertEqual(round_div_signed(3, 2, frac_bits=0), 2)
        self.assertEqual(round_div_signed(-3, 2, frac_bits=0), -2)

    def test_overmod_exact_boundary(self):
        r = dwell_from_ab(a_num=500000, b_num=500000, vdc_raw=100)
        self.assertEqual(r["sum_num"], r["base"])
        self.assertEqual(r["overmodulated"], 0)
        self.assertEqual((r["t1"], r["t2"]), (ONE_F32 // 2, ONE_F32 // 2))

    def test_sum_base_minus_equal_plus_one(self):
        cases = [
            (499999, 500000, 999999, 0, 1000000),
            (500000, 500000, 1000000, 0, 1000000),
            (500001, 500000, 1000001, 1, 1000001),
        ]
        for a_num, b_num, expected_sum, overmodulated, denominator in cases:
            with self.subTest(delta=expected_sum - 1000000):
                r = dwell_from_ab(a_num, b_num, 100)
                self.assertEqual(r["sum_num"], expected_sum)
                self.assertEqual(r["base"], 1000000)
                self.assertEqual(r["overmodulated"], overmodulated)
                self.assertEqual(r["denominator"], denominator)

    def test_full_top_sum_base_minus_equal_plus_one(self):
        cases = [
            (2345, 4059, 7033, -1, 0),
            (2, 0, 3, 0, 0),
            (544, 941, 1631, 1, 1),
        ]
        for A, B, vdc_raw, expected_delta, expected_overmod in cases:
            with self.subTest(delta=expected_delta):
                r = svpwm_step(A, B, vdc_raw)
                self.assertEqual(r["sum_num"] - r["base"], expected_delta)
                self.assertEqual(r["overmodulated"], expected_overmod)

    def test_negative_dwell_and_duty_are_not_clamped(self):
        # cmp1=-1 selects sector 1 while rounded XYZ gives a small negative Z.
        r = svpwm_step(24903, 43132, 1)
        self.assertEqual(r["sector"], 1)
        self.assertLess(r["a_num"], 0)
        self.assertLess(r["t1"], 0)
        self.assertLess(r["M"], 0)
        self.assertLess(r["duty_u"], 0)

    def test_duty_mapping_keeps_explicit_negative_value(self):
        r = duty_from_sector(2, 3 * ONE_F32, 0)
        self.assertEqual(r["L"], -ONE_F32)
        self.assertEqual(r["duty_u"], -(1 << 24))

    def test_invalid_vdc_has_fixed_zero_error_result(self):
        for vdc_raw in (0, -1):
            with self.subTest(vdc_raw=vdc_raw):
                r = svpwm_step(123, -456, vdc_raw)
                self.assertEqual(r["error_code"], 1)
                self.assertEqual(r["sector"], 0)
                self.assertEqual(
                    (r["duty_u"], r["duty_v"], r["duty_w"]), (0, 0, 0)
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
