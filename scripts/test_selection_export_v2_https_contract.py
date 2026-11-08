"""Pure offline report validation; no subprocess, socket or fixture invocation."""
import unittest

from selection_export_v2_https_contract import AcceptanceRefusal, CHECKS, validate_result


class SelectionHttpsContractTests(unittest.TestCase):
    @staticmethod
    def report():
        return dict(status='completed', syntheticOnly=True,
                    selectionExportV2Acceptance=True, owners=2, assetCount=51,
                    digest='python-sha256-stdin', nativeDialog='not-exercised',
                    checks={name: True for name in CHECKS})

    def test_complete_report_accepted(self):
        validate_result(self.report())

    def test_missing_every_field_refused(self):
        for key in self.report():
            with self.subTest(key=key):
                value = self.report()
                del value[key]
                with self.assertRaises(AcceptanceRefusal):
                    validate_result(value)

    def test_every_check_must_be_present_true_and_boolean(self):
        for key in CHECKS:
            for replacement in (False, 1, 'true', None):
                with self.subTest(key=key, replacement=replacement):
                    value = self.report()
                    value['checks'][key] = replacement
                    with self.assertRaises(AcceptanceRefusal):
                        validate_result(value)
            value = self.report()
            del value['checks'][key]
            with self.assertRaises(AcceptanceRefusal):
                validate_result(value)

    def test_boolean_counts_and_integer_flags_refused(self):
        for key in ('owners', 'assetCount', 'syntheticOnly',
                    'selectionExportV2Acceptance'):
            value = self.report()
            value[key] = True if key in ('owners', 'assetCount') else 1
            with self.assertRaises(AcceptanceRefusal):
                validate_result(value)

    def test_extra_fields_and_checks_refused(self):
        value = self.report()
        value['payload'] = 'must not be accepted as a report'
        with self.assertRaises(AcceptanceRefusal):
            validate_result(value)
        value = self.report()
        value['checks']['unreviewed'] = True
        with self.assertRaises(AcceptanceRefusal):
            validate_result(value)

    def test_malformed_or_nonterminal_reports_refused(self):
        for value in (None, [], {}, 'completed',
                      dict(self.report(), status='pending'),
                      dict(self.report(), checks=[]),
                      dict(self.report(), nativeDialog='passed'),
                      dict(self.report(), assetCount=50)):
            with self.assertRaises(AcceptanceRefusal):
                validate_result(value)


if __name__ == '__main__':
    unittest.main()
