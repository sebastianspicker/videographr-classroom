from __future__ import annotations

import sys
import unittest
from pathlib import Path

# verify_public_hygiene imports its sibling module by bare name.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from verify_public_hygiene import _local_link_target


class LocalLinkTargetTests(unittest.TestCase):
    def test_blank_target_has_no_local_target(self) -> None:
        self.assertIsNone(_local_link_target(" "))

    def test_relative_target_with_title_is_kept(self) -> None:
        self.assertEqual(_local_link_target('docs/a.md "Title"'), "docs/a.md")


if __name__ == "__main__":
    unittest.main()
