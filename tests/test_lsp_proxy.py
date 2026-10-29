import importlib.util
import io
import pathlib
import unittest

spec = importlib.util.spec_from_file_location("proxy", pathlib.Path(__file__).parents[1] / "scripts/lsp-path-proxy.py")
proxy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(proxy)


class ProxyTests(unittest.TestCase):
    def test_workspace_edits_and_boundaries(self):
        value = {"changes": {"file:///mnt/p/a%20b.tex": [{"newText": "α"}]}, "rootPath": "/mnt/p", "other": "/mnt/project"}
        mapped = proxy.rewrite_value(value, "/mnt/p", "/work")
        self.assertIn("file:///work/a%20b.tex", mapped["changes"])
        self.assertEqual(mapped["other"], "/mnt/project")
        self.assertEqual(proxy.rewrite_value(mapped, "/work", "/mnt/p"), value)

    def test_root_mount(self):
        self.assertEqual(proxy.rewrite_value("file:///etc/a", "/", "/mnt/root"), "file:///mnt/root/etc/a")
        self.assertEqual(proxy.rewrite_value("/mnt/root/etc/a", "/mnt/root", "/"), "/etc/a")

    def test_unicode_framing(self):
        stream = io.BytesIO()
        value = {"jsonrpc": "2.0", "id": 1, "result": "αβ"}
        proxy.write_message(stream, value)
        stream.seek(0)
        self.assertEqual(proxy.read_message(stream), value)


if __name__ == "__main__":
    unittest.main()
