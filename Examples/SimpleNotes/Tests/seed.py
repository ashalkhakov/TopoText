# seed.py <service root>: three folders (one in another) and four notes, plain text only (as
# a client that knows nothing of TopoText would write them), for trying
# the app out and for its self-test.
import json, urllib.request, uuid, sys
root = sys.argv[1]
def post(path, body):
    r = urllib.request.Request(root + path, data=json.dumps(body).encode(), method='POST', headers={'Content-Type': 'application/json'})
    urllib.request.urlopen(r).read()
home = str(uuid.uuid4()); work = str(uuid.uuid4()); projects = str(uuid.uuid4())
post('Folders', {'Id': home, 'Name': 'Home', 'Created': '2026-10-06T08:00:00Z'})
post('Folders', {'Id': work, 'Name': 'Work', 'Created': '2026-10-06T08:00:00Z'})
# A folder in a folder.
post('Folders', {'Id': projects, 'Name': 'Projects', 'Created': '2026-10-06T08:00:00Z', 'Parent@odata.bind': 'Folders(\'%s\')' % work})
# Tags (#word) are in the text.
notes = [(home, 'Groceries\nmilk, eggs, bread\ncoffee beans', True), (home, 'Weekend\nfix the bike\ncall grandma #family', False),
         (work, 'Standup notes\nsync engine: done #work\nTopoText: merging works', False),
         (projects, 'Ideas\nnotes app that merges edits made offline #work #someday', False)]
for i, (f, body, pinned) in enumerate(notes):
    post('Notes', {'Id': str(uuid.uuid4()), 'Title': body.split('\n')[0], 'Body': body, 'Pinned': pinned,
                   'Created': '2026-10-06T08:00:00Z', 'Edited': '2026-10-06T0%d:00:00Z' % (9 - i), 'Folder@odata.bind': 'Folders(\'%s\')' % f})
