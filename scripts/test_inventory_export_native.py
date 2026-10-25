"""Static export contracts only; not compilation, dialog or filesystem acceptance."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent / 'flutter/windows/runner'


class InventoryExportNativeTests(unittest.TestCase):
    def test_digest_is_bounded_and_closes_provider(self):
        source = (ROOT / 'inventory_export_file.cpp').read_text(encoding='utf-8')
        for token in ('BCRYPT_SHA256_ALGORITHM', 'BCryptHash(',
                      'BCryptCloseAlgorithmProvider', '1024 * 1024'):
            self.assertIn(token, source)

    def test_writer_does_not_overwrite(self):
        source = (ROOT / 'inventory_export_file.cpp').read_text(encoding='utf-8')
        for token in ('CREATE_NEW', 'FlushFileBuffers', 'FileDispositionInfo',
                      'FILE_ATTRIBUTE_REPARSE_POINT', 'GetDriveTypeW',
                      'MB_ERR_INVALID_CHARS'):
            self.assertIn(token, source)
        for token in ('CREATE_ALWAYS', 'TRUNCATE_EXISTING', 'DeleteFileW('):
            self.assertNotIn(token, source)

    def test_dialogs_cancel_without_exposing_paths(self):
        source = (ROOT / 'inventory_export_channel.cpp').read_text(encoding='utf-8')
        for token in ('asset-desk-inventory.json', 'ERROR_CANCELLED',
                      'result->Success();', 'FOS_NOTESTFILECREATE',
                      'result->Success(EncodableValue(true))'):
            self.assertIn(token, source)
        self.assertNotIn('result->Success(EncodableValue(path))', source)
        self.assertIn('IFileOpenDialog', source)
        self.assertIn('FOS_ALLOWMULTISELECT | FOS_PICKFOLDERS', source)

    def test_inspection_reader_is_bounded_and_read_only(self):
        source = (ROOT / 'inventory_export_file.cpp').read_text(encoding='utf-8').split('bool ReadInventoryJson(', 1)[1]
        for token in ('GENERIC_READ', 'FILE_SHARE_READ', 'OPEN_EXISTING',
                      'FILE_FLAG_OPEN_REPARSE_POINT', 'GetFileType(file) == FILE_TYPE_DISK',
                      'GetFileSizeEx', 'size.QuadPart <= 1024 * 1024', 'CloseHandle(file)',
                      'if (!read) bytes->clear()'):
            self.assertIn(token, source)
        for token in ('GENERIC_WRITE', 'CREATE_NEW', 'WriteFile(', 'DeleteFile'):
            self.assertNotIn(token, source)

    def test_channel_lifecycle_and_build_inputs(self):
        source = (ROOT / 'flutter_window.cpp').read_text(encoding='utf-8')
        self.assertIn('CreateInventoryExportChannel', source)
        self.assertLess(source.index('export_channel_.reset()'),
                        source.index('flutter_controller_ = nullptr'))
        cmake = (ROOT / 'CMakeLists.txt').read_text(encoding='utf-8')
        for token in ('inventory_export_file.cpp', 'inventory_export_channel.cpp',
                      'bcrypt.lib', 'ole32.lib', 'shell32.lib'):
            self.assertIn(token, cmake)


if __name__ == '__main__':
    unittest.main()
