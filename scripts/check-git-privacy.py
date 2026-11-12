#!/usr/bin/env python3
"""Fail without printing identities unless author and committer are private alt identities."""
import subprocess
import sys

NAME = '9pbpsvr6f9-alt'
EMAIL = '289419752+9pbpsvr6f9-alt@users.noreply.github.com'

def check(identity):
    name, email = identity.split('\t')
    if name != NAME or email != EMAIL:
        sys.exit('Privacy check failed: use the approved alt name and GitHub no-reply email.')

if len(sys.argv) == 2:
    lines = subprocess.check_output(['git', 'log', '--format=%an%x09%ae%n%cn%x09%ce', sys.argv[1]], text=True).splitlines()
    if not lines:
        sys.exit('No commits to verify.')
    for line in lines:
        check(line)
else:
    for role in ('AUTHOR', 'COMMITTER'):
        ident = subprocess.check_output(['git', 'var', f'GIT_{role}_IDENT'], text=True)
        name, tail = ident.rsplit(' <', 1)
        check(name + '\t' + tail.split('>', 1)[0])
print('Git privacy check passed.')
