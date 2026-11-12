#!/usr/bin/env python3
"""Update pinned web code and record reference changes for an update PR; never merge."""
import os
import re
import subprocess
from pathlib import Path

SOURCES = [('Viren070/AIOStreams', 'web/AIOSTREAMS_REF'),
           ('mickey2266/AIOStreamsTVOS', 'web/TVOS_REFERENCE_REF')]

def main():
    notes = ['Scheduled upstream check. Review native and web compatibility before merging.', '']
    for repo, filename in SOURCES:
        head = subprocess.check_output(['git', 'ls-remote', f'https://github.com/{repo}.git', 'refs/heads/main'], text=True).split()[0]
        if not re.fullmatch('[0-9a-f]{40}', head):
            raise ValueError('Invalid upstream commit')
        path = Path(filename)
        old = path.read_text().strip()
        if head != old:
            path.write_text(head + '\n')
            notes.append(f'- {repo}: https://github.com/{repo}/compare/{old}...{head}')
    notes += ['', 'Official web changes build against the iOS compatibility patch. A patch conflict fails CI and needs repair.',
              'The TVOS_REFERENCE_REF is a last-seen marker, not an automatic native-code port. Review its comparison for applicable features.',
              'No automatic merge. The build is dispatched explicitly because GITHUB_TOKEN PRs do not trigger pull_request workflows.']
    Path(os.environ.get('RUNNER_TEMP', '/tmp'), 'upstream-pr.md').write_text('\n'.join(notes) + '\n')

if __name__ == '__main__':
    main()
