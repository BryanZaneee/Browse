#!/usr/bin/env python3
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys
sys.path.insert(0, str(Path(__file__).parent / "support"))
from world import World

class OwnershipTests(unittest.TestCase):
    def world(self, root):
        world = World("test", checkout=root)
        world.root = root / "owned"
        world.data = world.root / "data"
        world.owner["root"] = str(world.root)
        return world

    def test_identity_covers_checkout_and_name(self):
        with tempfile.TemporaryDirectory() as folder:
            a = World("test", checkout=folder)
            b = World("other", checkout=folder)
            c = World("test", checkout=folder + "/second")
            self.assertEqual(len({a.bundle, b.bundle, c.bundle}), 3)
            for invalid in ("../Browse", "", "test/name"):
                with self.assertRaises(ValueError): World(invalid)

    def test_foreign_marker_and_live_process_refuse_cleanup(self):
        with tempfile.TemporaryDirectory() as folder:
            world = self.world(Path(folder))
            world.root.mkdir()
            marker = world.root / "owner.json"
            marker.write_text(json.dumps(world.owner | {"world": "foreign"}))
            with self.assertRaises(RuntimeError): world.wipe()
            self.assertTrue(marker.exists())
            marker.write_text(json.dumps(world.owner))
            with patch.object(world, "pids", return_value=[123]):
                with self.assertRaises(RuntimeError): world.wipe()
            self.assertTrue(marker.exists())

    def test_visible_launch_timeout_is_an_error(self):
        with tempfile.TemporaryDirectory() as folder:
            world = self.world(Path(folder))
            with patch.object(world, "verify"), patch.object(world, "pids", return_value=[]), patch("world.subprocess.run"), patch("world.time.sleep"):
                with self.assertRaises(RuntimeError): world.launch(hidden=False)

    def test_live_executable_uses_bundle_name_and_canonical_path(self):
        world = World("pid-check")
        listing = f"  123 {world.app.resolve()}/Contents/MacOS/Browse\n 124 /Applications/Browse.app/Contents/MacOS/Browse\n"
        with patch("world.subprocess.run") as run:
            run.return_value.stdout = listing
            self.assertEqual(world.pids(), [123])

    def test_duplicate_owner_cannot_launch_or_wipe(self):
        with tempfile.TemporaryDirectory() as folder:
            a, b = self.world(Path(folder)), self.world(Path(folder))
            a.lock()
            for operation in (b.prepare, b.launch, b.wipe):
                with self.assertRaises(RuntimeError): operation()

    def test_symlinked_data_and_marker_refused(self):
        for resource in ("data", "owner.json"):
            with tempfile.TemporaryDirectory() as folder:
                world = self.world(Path(folder))
                world.root.mkdir()
                foreign = Path(folder) / "foreign"
                foreign.write_text("untouched")
                (world.root / "owner.json").write_text(json.dumps(world.owner))
                target = world.root / resource
                target.unlink(missing_ok=True)
                target.symlink_to(foreign)
                with self.assertRaises(RuntimeError): world.wipe()
                self.assertEqual(foreign.read_text(), "untouched")

    def test_symlink_root_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            world = self.world(root)
            target = root / "foreign"
            target.mkdir()
            world.root.symlink_to(target)
            with self.assertRaises(RuntimeError): world.wipe()
            self.assertTrue(target.exists())

    def test_cleanup_ignores_foreign_space_ids(self):
        with tempfile.TemporaryDirectory() as folder, tempfile.TemporaryDirectory() as home:
            world = self.world(Path(folder))
            world.root.mkdir()
            (world.root / "owner.json").write_text(json.dumps(world.owner))
            world.data.mkdir()
            (world.data / "spaces.json").write_text('[{"id":"foreign-production-id"}]')
            foreign = Path(home) / "Library/WebKit/com.bryanzaneee.browse/WebsiteDataStore/foreign-production-id"
            foreign.mkdir(parents=True)
            owned = Path(home) / "Library/WebKit" / world.bundle
            owned.mkdir()
            cookies = Path(home) / "Library/HTTPStorages" / (world.bundle + ".binarycookies")
            cookies.parent.mkdir(parents=True)
            cookies.write_text("synthetic")
            with patch("world.Path.home", return_value=Path(home)), patch.object(world, "pids", return_value=[]), patch("world.subprocess.run"):
                world.wipe()
            self.assertTrue(foreign.exists())
            self.assertFalse(owned.exists())
            self.assertFalse(cookies.exists())
            self.assertFalse(world.root.exists())

if __name__ == "__main__": unittest.main()
