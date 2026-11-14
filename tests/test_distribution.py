import importlib.util
import json
import plistlib
import tempfile
import unittest
import zipfile
from pathlib import Path

spec = importlib.util.spec_from_file_location('source', Path(__file__).resolve().parents[1] / 'scripts/update-source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)

class SourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        for filename, bundle, _ in source.APPS:
            self.ipa(filename, bundle)

    def ipa(self, filename, bundle, version='0.2.10'):
        info = dict(CFBundleIdentifier=bundle, CFBundleShortVersionString=version,
                    CFBundleVersion='10', MinimumOSVersion='18.0',
                    NSLocalNetworkUsageDescription='Connect to local media servers.')
        with zipfile.ZipFile(self.folder / filename, 'w') as z:
            z.writestr('Payload/Test.app/Info.plist', plistlib.dumps(info))

    def test_sizes_identity_permissions_and_version_match_actual_ipas(self):
        feed = source.generate('v0.2.10', self.folder)
        self.assertEqual(len(feed['apps']), len(source.APPS))
        for app, (filename, bundle, _) in zip(feed['apps'], source.APPS):
            version = app['versions'][0]
            self.assertEqual(app['bundleIdentifier'], bundle)
            self.assertEqual(app['developerName'], '9pbpsvr6f9-alt')
            self.assertEqual(version['size'], (self.folder / filename).stat().st_size)
            self.assertEqual(version['buildVersion'], '10')
            self.assertIn('/v0.2.10/', version['downloadURL'])
            self.assertIn('NSLocalNetworkUsageDescription', app['appPermissions']['privacy'])
        self.assertNotIn('@', json.dumps(feed))

    def test_an_app_no_longer_built_leaves_the_source(self):
        old = source.generate('v0.2.10', self.folder)
        old['apps'].append({'bundleIdentifier': 'io.github.aiostreams-ios.tv', 'versions': [{'version': '0.2.10'}]})
        old['featuredApps'].append('io.github.aiostreams-ios.tv')
        for filename, bundle, _ in source.APPS:
            self.ipa(filename, bundle, '0.2.11')
        new = source.generate('v0.2.11', self.folder, old)
        self.assertEqual([a['bundleIdentifier'] for a in new['apps']], [b for _, b, _ in source.APPS])
        self.assertNotIn('io.github.aiostreams-ios.tv', json.dumps(new))

    def test_source_address_is_fixed_and_unredirected(self):
        feed = source.generate('v0.2.10', self.folder)
        raw = 'https://raw.githubusercontent.com/9pbpsvr6f9-alt/aiostreams-ios/main/'
        # FlareStore keeps the address a redirect ends on, so nothing here may be a release's.
        self.assertEqual(feed['sourceURL'], raw + 'altstore/source.json')
        self.assertEqual(feed['iconURL'], raw + 'altstore/icon.png')
        self.assertNotIn('latest/download', json.dumps(feed))

    def test_notes_leave_out_the_source_bookkeeping_commit(self):
        feed = source.generate('v0.2.10', self.folder, notes='Fix a thing\nFlareStore source: v0.2.9\n')
        notes = feed['apps'][0]['versions'][0]['localizedDescription']
        self.assertIn('Fix a thing', notes)
        self.assertNotIn('FlareStore source', notes)

    def test_rebuild_deduplicates_history(self):
        old = source.generate('v0.2.10', self.folder)
        new = source.generate('v0.2.10', self.folder, old)
        self.assertEqual(len(new['apps'][0]['versions']), 1)

    def test_retains_old_downloads_when_new_version_is_published(self):
        old = source.generate('v0.2.10', self.folder)
        for filename, bundle, _ in source.APPS:
            self.ipa(filename, bundle, version='0.2.11')
        new = source.generate('v0.2.11', self.folder, old)
        self.assertEqual([v['version'] for v in new['apps'][0]['versions']], ['0.2.11', '0.2.10'])

    def test_rejects_feed_downgrade(self):
        old = source.generate('v0.2.10', self.folder)
        old['apps'][0]['versions'][0]['version'] = '0.2.12'
        with self.assertRaises(ValueError):
            source.generate('v0.2.10', self.folder, old)

    def test_rejects_wrong_bundle_and_tag_version(self):
        with self.assertRaises(ValueError):
            source.generate('v0.2.11', self.folder)
        self.ipa('AIOStreams.ipa', 'wrong.bundle')
        with self.assertRaises(ValueError):
            source.generate('v0.2.10', self.folder)

    def test_rejects_missing_plist_and_unsafe_tag(self):
        with self.assertRaises(ValueError):
            source.generate('../bad', self.folder)
        with zipfile.ZipFile(self.folder / 'AIOStreams.ipa', 'w'):
            pass
        with self.assertRaises(ValueError):
            source.generate('v0.2.10', self.folder)

    def test_release_notes_news_and_screenshots(self):
        notes = 'Add downloads on iOS\n\n- Show the volume toast\nCo-Authored-By: Someone <x@example.com>\nAdd downloads on iOS\n'
        feed = source.generate('v0.2.10', self.folder, notes=notes)
        text = feed['apps'][0]['versions'][0]['localizedDescription']
        self.assertIn('• Add downloads on iOS', text)
        self.assertIn('• Show the volume toast', text)
        self.assertEqual(text.count('Add downloads on iOS'), 1)
        self.assertNotIn('@', json.dumps(feed))
        self.assertEqual(feed['news'][0]['identifier'], 'release-v0.2.10')
        self.assertEqual(feed['news'][0]['caption'], 'Add downloads on iOS')
        repo = Path(__file__).resolve().parents[1]
        for app in feed['apps']:
            self.assertTrue(app['screenshotURLs'])
            for url in app['screenshotURLs'] + app.get('screenshots', {}).get('ipad', []):
                name = url.rsplit('/docs/', 1)[1]
                self.assertTrue((repo / 'docs' / name).is_file(), url)

    def test_news_and_history_carry_over(self):
        feed = source.generate('v0.2.10', self.folder)
        for n in range(11, 70):
            for filename, bundle, _ in source.APPS:
                self.ipa(filename, bundle, version=f'0.2.{n}')
            feed = source.generate(f'v0.2.{n}', self.folder, feed)
        self.assertEqual(feed['news'][0]['identifier'], 'release-v0.2.69')
        self.assertEqual(len(feed['news']), source.NEWS)
        versions = [v['version'] for v in feed['apps'][0]['versions']]
        self.assertEqual(len(versions), source.HISTORY)
        self.assertEqual(versions[0], '0.2.69')

    def test_without_notes_still_reads_well(self):
        feed = source.generate('v0.2.10', self.folder)
        self.assertIn('Fixes and improvements.', feed['apps'][0]['versions'][0]['localizedDescription'])

if __name__ == '__main__':
    unittest.main()
