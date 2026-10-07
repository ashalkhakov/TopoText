#!/usr/bin/env python3
"""The Xcode side of TopoText, written from this file:

  TopoText.xcodeproj                        TopoText and TopoTextSync, frameworks
                                            for macOS and iOS
  Examples/SimpleNotes/SimpleNotes.xcodeproj  SimpleNotes for macOS and iOS, and
                                            simplenotes-server
  TopoText.xcworkspace                      both, and ODataKit's project beside
                                            this checkout (../ODataKit)

and their shared schemes. Object IDs are made from names, so running it
again writes the same files: change this, run it, commit what it wrote.

  python3 Scripts/xcodeproj.py
"""
import hashlib, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ODataKit.xcodeproj's targets and their products, by name (its IDs are fixed).
ODATAKIT = {
    'ODataKit': ('AA0000000000000000000006', 'AA0000000000000000000007'),
    'ODataIncrementalStore': ('AA0000000000000000000002', 'AA0000000000000000000003'),
    'ODataService': ('AA000000000000000000000A', 'AA000000000000000000000B'),
    'OTelKit': ('4CBB61F9CEEAF8A9C5A1F7CF', 'D7BA1954D987FDFF19FEE609'),
    'HTTPServerKit': ('9828CC078A88AE7706B232C7', 'A21CEFC6F685318B7798AD60'),
    'ODataSync': ('7F1CE30E03D845ACEF6B15CD', '5C30F5597E6C2517354354B7'),
}
ODATAKIT_ORDER = ['ODataKit', 'OTelKit', 'ODataIncrementalStore', 'HTTPServerKit', 'ODataService', 'ODataSync']


def oid(*parts):
    return hashlib.md5('/'.join(parts).encode()).hexdigest()[:24].upper()


def quote(s):
    s = str(s)
    if re.fullmatch(r'[A-Za-z0-9_$/.:]+', s):
        return s
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def write_value(v, indent):
    pad = '\t' * indent
    if isinstance(v, dict):
        out = '{\n'
        for k, x in v.items():
            out += pad + '\t' + quote(k) + ' = ' + write_value(x, indent + 1) + ';\n'
        return out + pad + '}'
    if isinstance(v, list):
        out = '(\n'
        for x in v:
            out += pad + '\t' + write_value(x, indent + 1) + ',\n'
        return out + pad + ')'
    return quote(v)


class Project:
    def __init__(self, name, path):
        self.name, self.path = name, path
        self.objects = {}
        self.comments = {}

    def add(self, key, comment, obj):
        self.objects[key] = obj
        self.comments[key] = comment
        return key

    def write(self):
        os.makedirs(os.path.join(ROOT, self.path), exist_ok=True)
        by_isa = {}
        for k, o in self.objects.items():
            by_isa.setdefault(o['isa'], []).append(k)
        out = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n'
        for isa in sorted(by_isa):
            out += '\n/* Begin %s section */\n' % isa
            for k in sorted(by_isa[isa]):
                out += '\t\t%s /* %s */ = %s;\n' % (k, self.comments[k], write_value(self.objects[k], 2))
            out += '/* End %s section */\n' % isa
        out += '\t};\n\trootObject = %s /* Project object */;\n}\n' % self.root
        with open(os.path.join(ROOT, self.path, 'project.pbxproj'), 'w') as f:
            f.write(out)


FILETYPES = {'.m': 'sourcecode.c.objc', '.h': 'sourcecode.c.h', '.xib': 'file.xib', '.plist': 'text.plist.xml',
             '.xcconfig': 'text.xcconfig', '.py': 'text.script.python', '.md': 'net.daringfireball.markdown',
             '.icns': 'image.icns', '.png': 'image.png'}


def file_ref(p, path, name=None):
    key = oid(p.name, 'file', path)
    ext = os.path.splitext(path)[1]
    obj = {'isa': 'PBXFileReference', 'lastKnownFileType': FILETYPES.get(ext, 'text'), 'path': path, 'sourceTree': '<group>'}
    if name:
        obj['name'] = name
    return p.add(key, os.path.basename(path), obj)


def model_ref(p, path):
    """A versioned model: each version in it, the current one as its
    .xccurrentversion says."""
    d = os.path.join(ROOT, os.path.dirname(p.path), path)
    versions = sorted(v for v in os.listdir(d) if v.endswith('.xcdatamodel'))
    with open(os.path.join(d, '.xccurrentversion')) as f:
        current = re.search(r'<string>(.*?)</string>', f.read()).group(1)
    children = {v: p.add(oid(p.name, 'model', path, v), v,
                         {'isa': 'PBXFileReference', 'lastKnownFileType': 'wrapper.xcdatamodel', 'path': v, 'sourceTree': '<group>'})
                for v in versions}
    return p.add(oid(p.name, 'model', path), os.path.basename(path),
                 {'isa': 'XCVersionGroup', 'children': [children[v] for v in versions], 'currentVersion': children[current],
                  'path': path, 'sourceTree': '<group>', 'versionGroupType': 'wrapper.xcdatamodel'})


def group(p, name, children, path=None):
    obj = {'isa': 'PBXGroup', 'children': children, 'sourceTree': '<group>'}
    if path:
        obj['path'] = path
    else:
        obj['name'] = name
    return p.add(oid(p.name, 'group', name), name, obj)


def config_list(p, owner, debug, release, base_debug=None, base_release=None):
    ids = []
    for conf, settings, base in (('Debug', debug, base_debug), ('Release', release, base_release)):
        obj = {'isa': 'XCBuildConfiguration', 'buildSettings': settings, 'name': conf}
        if base:
            obj['baseConfigurationReference'] = base
        ids.append(p.add(oid(p.name, 'config', owner, conf), conf, obj))
    return p.add(oid(p.name, 'configlist', owner), 'Build configuration list for %s' % owner,
                 {'isa': 'XCConfigurationList', 'buildConfigurations': ids, 'defaultConfigurationIsVisible': '0',
                  'defaultConfigurationName': 'Release'})


def build_file(p, target, phase, ref, comment, settings=None):
    obj = {'isa': 'PBXBuildFile', 'fileRef': ref}
    if settings:
        obj['settings'] = settings
    return p.add(oid(p.name, 'buildfile', target, phase, ref), '%s in %s' % (comment, phase), obj)


def phase(p, target, isa, name, files, extra=None):
    obj = {'isa': isa, 'buildActionMask': '2147483647', 'files': files, 'runOnlyForDeploymentPostprocessing': '0'}
    if extra:
        obj.update(extra)
    return p.add(oid(p.name, 'phase', target, name), name, obj)


class Remote:
    """Another project this one references: its products, and its targets to depend on."""
    def __init__(self, p, name, path, targets):
        self.p, self.name = p, name
        self.ref = p.add(oid(p.name, 'remote', name), name + '.xcodeproj',
                         {'isa': 'PBXFileReference', 'lastKnownFileType': 'wrapper.pb-project', 'name': name + '.xcodeproj',
                          'path': path, 'sourceTree': '<group>'})
        self.products = {}
        self.targets = targets
        for t, (target_id, product_id) in targets.items():
            proxy = p.add(oid(p.name, 'remote', name, t, 'productproxy'), 'PBXContainerItemProxy',
                          {'isa': 'PBXContainerItemProxy', 'containerPortal': self.ref, 'proxyType': '2',
                           'remoteGlobalIDString': product_id, 'remoteInfo': t})
            self.products[t] = p.add(oid(p.name, 'remote', name, t, 'product'), t + '.framework',
                                     {'isa': 'PBXReferenceProxy', 'fileType': 'wrapper.framework', 'path': t + '.framework',
                                      'remoteRef': proxy, 'sourceTree': 'BUILT_PRODUCTS_DIR'})
        self.group = p.add(oid(p.name, 'remote', name, 'products'), 'Products',
                           {'isa': 'PBXGroup', 'children': [self.products[t] for t in targets], 'name': 'Products', 'sourceTree': '<group>'})

    def dependency(self, target, t):
        p = self.p
        proxy = p.add(oid(p.name, 'dep', target, self.name, t, 'proxy'), 'PBXContainerItemProxy',
                      {'isa': 'PBXContainerItemProxy', 'containerPortal': self.ref, 'proxyType': '1',
                       'remoteGlobalIDString': self.targets[t][0], 'remoteInfo': t})
        return p.add(oid(p.name, 'dep', target, self.name, t), 'PBXTargetDependency',
                     {'isa': 'PBXTargetDependency', 'name': t, 'targetProxy': proxy})


def native_target(p, name, product_type, product_name, product_ext, phases, deps, configlist, explicit_type):
    product = p.add(oid(p.name, 'product', name), product_name + product_ext,
                    {'isa': 'PBXFileReference', 'explicitFileType': explicit_type, 'includeInIndex': '0',
                     'path': product_name + product_ext, 'sourceTree': 'BUILT_PRODUCTS_DIR'})
    tid = oid(p.name, 'target', name)
    p.add(tid, name, {'isa': 'PBXNativeTarget', 'buildConfigurationList': configlist, 'buildPhases': phases, 'buildRules': [],
                      'dependencies': deps, 'name': name, 'productName': product_name, 'productReference': product,
                      'productType': product_type})
    return tid, product


def project_object(p, main_group, products_group, targets, remotes, configlist):
    p.root = p.add(oid(p.name, 'project'), 'Project object',
                   {'isa': 'PBXProject', 'attributes': {'BuildIndependentTargetsInParallel': '1', 'LastUpgradeCheck': '1600'},
                    'buildConfigurationList': configlist, 'compatibilityVersion': 'Xcode 14.0', 'developmentRegion': 'en',
                    'hasScannedForEncodings': '0', 'knownRegions': ['en', 'Base'], 'mainGroup': main_group,
                    'productRefGroup': products_group, 'projectDirPath': '',
                    'projectReferences': [{'ProductGroup': r.group, 'ProjectRef': r.ref} for r in remotes],
                    'projectRoot': '', 'targets': targets})


FRAMEWORK_SETTINGS = {
    'DEFINES_MODULE': 'NO', 'DYLIB_COMPATIBILITY_VERSION': '1', 'DYLIB_CURRENT_VERSION': '1', 'DYLIB_INSTALL_NAME_BASE': '@rpath',
    'INSTALL_PATH': '$(LOCAL_LIBRARY_DIR)/Frameworks', 'SKIP_INSTALL': 'YES', 'SDKROOT': 'macosx',
    'SUPPORTED_PLATFORMS': 'macosx iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO', 'TARGETED_DEVICE_FAMILY': '1,2',
    'LD_RUNPATH_SEARCH_PATHS': ['@executable_path/../Frameworks', '@loader_path/Frameworks', '@loader_path/..'],
    'LD_RUNPATH_SEARCH_PATHS[sdk=iphone*]': ['$(inherited)', '@executable_path/Frameworks', '@loader_path/Frameworks'],
    'INFOPLIST_KEY_NSHumanReadableCopyright': 'TopoText',
}

# --------------------------------------------------------------------- TopoText


def topotext():
    p = Project('TopoText', 'TopoText.xcodeproj')
    odk = Remote(p, 'ODataKit', '../ODataKit/ODataKit.xcodeproj', {k: ODATAKIT[k] for k in ('ODataKit', 'ODataSync')})
    configs = [file_ref(p, 'Xcode/Configs/%s.xcconfig' % c, '%s.xcconfig' % c) for c in ('Common', 'Debug', 'Release')]
    tt = {f: file_ref(p, 'Sources/TopoText/' + f) for f in ('TopoText.m', 'TTCoding.m', 'TTInternal.h', 'include/TopoText/TopoText.h')}
    sy = {f: file_ref(p, 'Sources/TopoTextSync/' + f) for f in ('TTSyncResolver.m', 'include/TopoTextSync/TopoTextSync.h')}
    for k in tt:
        p.objects[tt[k]]['name'] = os.path.basename(k)
    for k in sy:
        p.objects[sy[k]]['name'] = os.path.basename(k)

    targets, products = [], []
    # TopoText
    hdr = phase(p, 'TopoText', 'PBXHeadersBuildPhase', 'Headers',
                [build_file(p, 'TopoText', 'Headers', tt['include/TopoText/TopoText.h'], 'TopoText.h', {'ATTRIBUTES': ['Public']}),
                 build_file(p, 'TopoText', 'Headers', tt['TTInternal.h'], 'TTInternal.h')])
    src = phase(p, 'TopoText', 'PBXSourcesBuildPhase', 'Sources',
                [build_file(p, 'TopoText', 'Sources', tt[f], f) for f in ('TopoText.m', 'TTCoding.m')])
    fw = phase(p, 'TopoText', 'PBXFrameworksBuildPhase', 'Frameworks', [])
    s = dict(FRAMEWORK_SETTINGS, PRODUCT_BUNDLE_IDENTIFIER='io.github.ashalkhakov.TopoText',
             HEADER_SEARCH_PATHS=['$(SRCROOT)/Sources/TopoText', '$(SRCROOT)/Sources/TopoText/include/TopoText'])
    tid, prod = native_target(p, 'TopoText', 'com.apple.product-type.framework', 'TopoText', '.framework', [hdr, src, fw], [],
                              config_list(p, 'TopoText', s, s), 'wrapper.framework')
    targets.append(tid); products.append(prod)
    topotext_target, topotext_product = tid, prod

    # TopoTextSync
    hdr = phase(p, 'TopoTextSync', 'PBXHeadersBuildPhase', 'Headers',
                [build_file(p, 'TopoTextSync', 'Headers', sy['include/TopoTextSync/TopoTextSync.h'], 'TopoTextSync.h', {'ATTRIBUTES': ['Public']})])
    src = phase(p, 'TopoTextSync', 'PBXSourcesBuildPhase', 'Sources', [build_file(p, 'TopoTextSync', 'Sources', sy['TTSyncResolver.m'], 'TTSyncResolver.m')])
    fw = phase(p, 'TopoTextSync', 'PBXFrameworksBuildPhase', 'Frameworks',
               [build_file(p, 'TopoTextSync', 'Frameworks', topotext_product, 'TopoText.framework')] +
               [build_file(p, 'TopoTextSync', 'Frameworks', odk.products[k], k + '.framework') for k in ('ODataKit', 'ODataSync')])
    proxy = p.add(oid(p.name, 'dep', 'TopoTextSync', 'TopoText', 'proxy'), 'PBXContainerItemProxy',
                  {'isa': 'PBXContainerItemProxy', 'containerPortal': oid(p.name, 'project'), 'proxyType': '1',
                   'remoteGlobalIDString': topotext_target, 'remoteInfo': 'TopoText'})
    local = p.add(oid(p.name, 'dep', 'TopoTextSync', 'TopoText'), 'PBXTargetDependency',
                  {'isa': 'PBXTargetDependency', 'target': topotext_target, 'targetProxy': proxy})
    s = dict(FRAMEWORK_SETTINGS, PRODUCT_BUNDLE_IDENTIFIER='io.github.ashalkhakov.TopoTextSync',
             HEADER_SEARCH_PATHS=['$(SRCROOT)/Sources/TopoTextSync/include/TopoTextSync'])
    tid, prod = native_target(p, 'TopoTextSync', 'com.apple.product-type.framework', 'TopoTextSync', '.framework', [hdr, src, fw],
                              [local, odk.dependency('TopoTextSync', 'ODataKit'), odk.dependency('TopoTextSync', 'ODataSync')],
                              config_list(p, 'TopoTextSync', s, s), 'wrapper.framework')
    targets.append(tid); products.append(prod)

    products_group = group(p, 'Products', products)
    main = group(p, 'TopoText', [
        group(p, 'Sources', [group(p, 'TopoText-files', list(tt.values()), None), group(p, 'TopoTextSync-files', list(sy.values()), None)]),
        group(p, 'Configs', configs), group(p, 'Libraries', [odk.ref]), products_group])
    p.objects[oid(p.name, 'group', 'TopoText-files')]['name'] = 'TopoText'
    p.objects[oid(p.name, 'group', 'TopoTextSync-files')]['name'] = 'TopoTextSync'
    project_object(p, main, products_group, targets, [odk],
                   config_list(p, 'project', {}, {}, configs[1], configs[2]))
    p.write()
    scheme('TopoText.xcodeproj', 'TopoText', targets[0], 'TopoText.framework', 'TopoText.xcodeproj')
    scheme('TopoText.xcodeproj', 'TopoTextSync', targets[1], 'TopoTextSync.framework', 'TopoText.xcodeproj')
    return {'TopoText': (targets[0], products[0]), 'TopoTextSync': (targets[1], products[1])}

# ------------------------------------------------------------------ SimpleNotes


def simplenotes(topotext_ids):
    p = Project('SimpleNotes', 'Examples/SimpleNotes/SimpleNotes.xcodeproj')
    tt = Remote(p, 'TopoText', '../../TopoText.xcodeproj', topotext_ids)
    odk = Remote(p, 'ODataKit', '../../../ODataKit/ODataKit.xcodeproj', ODATAKIT)
    configs = [file_ref(p, '../../Xcode/Configs/%s.xcconfig' % c, '%s.xcconfig' % c) for c in ('Common', 'Debug', 'Release')]
    F = lambda path: file_ref(p, path, os.path.basename(path))
    shared = {n: F('Shared/' + n) for n in ('SNModel.h', 'SNModel.m', 'SNNote.h', 'SNNote.m', 'SNFolder.h', 'SNFolder.m', 'SNNotes.h',
                                           'SNNotes.m', 'SNResolver.h', 'SNResolver.m', 'SNRichText.h', 'SNRichText.m', 'SNCheck.h', 'SNCheck.m',
                                           'SNMigration.h', 'SNMigration.m')}
    model = model_ref(p, 'SimpleNotes.xcdatamodeld')
    appkit = {n: F('AppKit/' + n) for n in ('main.m', 'SNAppController.h', 'SNAppController.m', 'SNWindowController.h', 'SNWindowController.m',
                                           'SNTextView.h', 'SNTextView.m', 'SNSelfTest.h', 'SNSelfTest.m', 'MainMenu.xib', 'NotesWindow.xib', 'TextPanel.xib', 'Info.plist',
                                           'SimpleNotes-macOS.xcconfig')}
    ios = {n: F('iOS/' + n) for n in ('main.m', 'SNiOSControllers.h', 'SNiOSControllers.m', 'SNiOSSelfTest.h', 'SNiOSSelfTest.m',
                                     'SNEditorViewController.xib', 'Info.plist',
                                     'SimpleNotes-iOS.xcconfig')}
    icons = {n: F('Icons/' + n) for n in ('SimpleNotes.icns',)}
    server = {n: F('Server/' + n) for n in ('SNServer.m',)}
    tests = {n: F('Tests/' + n) for n in ('seed.py',)}

    frameworks = ['TopoText', 'TopoTextSync'] + ODATAKIT_ORDER
    def fw_ref(name):
        return (tt if name in tt.products else odk).products[name]
    def deps(target):
        return [(tt if n in tt.products else odk).dependency(target, n) for n in frameworks]

    def app(target, sources, resources, xcconfig, embed=True):
        src = phase(p, target, 'PBXSourcesBuildPhase', 'Sources',
                    [build_file(p, target, 'Sources', ref, comment) for ref, comment in sources])
        fw = phase(p, target, 'PBXFrameworksBuildPhase', 'Frameworks',
                   [build_file(p, target, 'Frameworks', fw_ref(n), n + '.framework') for n in frameworks])
        res = phase(p, target, 'PBXResourcesBuildPhase', 'Resources',
                    [build_file(p, target, 'Resources', ref, comment) for ref, comment in resources])
        phases = [src, fw, res]
        if embed:
            phases.append(phase(p, target, 'PBXCopyFilesBuildPhase', 'Embed Frameworks',
                                [build_file(p, target, 'Embed Frameworks', fw_ref(n), n + '.framework',
                                            {'ATTRIBUTES': ['CodeSignOnCopy', 'RemoveHeadersOnCopy']}) for n in frameworks],
                                {'dstPath': '', 'dstSubfolderSpec': '10', 'name': 'Embed Frameworks'}))
        return phases

    def sources_of(d, names):
        return [(d[n], n) for n in names]
    common = sources_of(shared, ['SNModel.m', 'SNNote.m', 'SNFolder.m', 'SNNotes.m', 'SNResolver.m', 'SNRichText.m', 'SNMigration.m']) + [(model, 'SimpleNotes.xcdatamodeld')]

    targets = []
    mac_phases = app('SimpleNotes', sources_of(appkit, ['main.m', 'SNAppController.m', 'SNWindowController.m', 'SNTextView.m', 'SNSelfTest.m'])
                     + sources_of(shared, ['SNCheck.m']) + common,
                     sources_of(appkit, ['MainMenu.xib', 'NotesWindow.xib', 'TextPanel.xib']) + sources_of(icons, ['SimpleNotes.icns']),
                     appkit['SimpleNotes-macOS.xcconfig'])
    tid, mac_product = native_target(p, 'SimpleNotes', 'com.apple.product-type.application', 'SimpleNotes', '.app', mac_phases,
                                     deps('SimpleNotes'), config_list(p, 'SimpleNotes', {}, {}, appkit['SimpleNotes-macOS.xcconfig'],
                                                                      appkit['SimpleNotes-macOS.xcconfig']), 'wrapper.application')
    targets.append(('SimpleNotes', tid, 'SimpleNotes.app'))

    ios_phases = app('SimpleNotes-iOS', sources_of(ios, ['main.m', 'SNiOSControllers.m', 'SNiOSSelfTest.m']) + common,
                     sources_of(ios, ['SNEditorViewController.xib']), ios['SimpleNotes-iOS.xcconfig'])
    tid, ios_product = native_target(p, 'SimpleNotes-iOS', 'com.apple.product-type.application', 'SimpleNotes-iOS', '.app', ios_phases,
                                     deps('SimpleNotes-iOS'), config_list(p, 'SimpleNotes-iOS', {}, {}, ios['SimpleNotes-iOS.xcconfig'],
                                                                          ios['SimpleNotes-iOS.xcconfig']), 'wrapper.application')
    p.objects[ios_product]['path'] = 'SimpleNotes.app'
    targets.append(('SimpleNotes-iOS', tid, 'SimpleNotes.app'))

    # The server: a tool; Xcode compiles its model beside it, where it looks.
    src = phase(p, 'simplenotes-server', 'PBXSourcesBuildPhase', 'Sources',
                [build_file(p, 'simplenotes-server', 'Sources', ref, c) for ref, c in
                 sources_of(server, ['SNServer.m']) + sources_of(shared, ['SNModel.m', 'SNNote.m', 'SNFolder.m', 'SNMigration.m']) + [(model, 'SimpleNotes.xcdatamodeld')]])
    fw = phase(p, 'simplenotes-server', 'PBXFrameworksBuildPhase', 'Frameworks',
               [build_file(p, 'simplenotes-server', 'Frameworks', fw_ref(n), n + '.framework') for n in frameworks])
    s = {'SDKROOT': 'macosx', 'SUPPORTED_PLATFORMS': 'macosx', 'PRODUCT_NAME': 'simplenotes-server', 'SKIP_INSTALL': 'YES',
         'GENERATE_INFOPLIST_FILE': 'NO', 'HEADER_SEARCH_PATHS': ['$(SRCROOT)/Shared'],
         'LD_RUNPATH_SEARCH_PATHS': ['@executable_path', '@loader_path']}
    tid, server_product = native_target(p, 'simplenotes-server', 'com.apple.product-type.tool', 'simplenotes-server', '', [src, fw],
                                        deps('simplenotes-server'), config_list(p, 'simplenotes-server', s, s), 'compiled.mach-o.executable')
    targets.append(('simplenotes-server', tid, 'simplenotes-server'))

    products_group = group(p, 'Products', [mac_product, ios_product, server_product])
    main = group(p, 'SimpleNotes', [
        group(p, 'Shared', list(shared.values()) + [model]),
        group(p, 'AppKit', list(appkit.values())),
        group(p, 'iOS', list(ios.values())),
        group(p, 'Server', list(server.values())),
        group(p, 'Tests', list(tests.values())),
        group(p, 'Configs', configs),
        group(p, 'Libraries', [tt.ref, odk.ref]),
        products_group])
    project_object(p, main, products_group, [t[1] for t in targets], [tt, odk],
                   config_list(p, 'project', {}, {}, configs[1], configs[2]))
    p.write()
    for name, tid, product in targets:
        scheme('Examples/SimpleNotes/SimpleNotes.xcodeproj', name, tid, product, 'SimpleNotes.xcodeproj', runnable=name != 'SimpleNotes-iOS' or True)


def scheme(project_path, name, target_id, product, container, runnable=False):
    ref = ('<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s" '
           'BlueprintName = "%s" ReferencedContainer = "container:%s"></BuildableReference>') % (target_id, product, name, container)
    launch = ('<BuildableProductRunnable runnableDebuggingMode = "0">%s</BuildableProductRunnable>' % ref) if runnable and product.endswith(('.app', 'server')) else ''
    xml = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            %s
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      %s
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''' % (ref, launch)
    d = os.path.join(ROOT, project_path, 'xcshareddata', 'xcschemes')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, name + '.xcscheme'), 'w') as f:
        f.write(xml)


def workspace():
    d = os.path.join(ROOT, 'TopoText.xcworkspace')
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, 'contents.xcworkspacedata'), 'w') as f:
        f.write('''<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:TopoText.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:Examples/SimpleNotes/SimpleNotes.xcodeproj">
   </FileRef>
   <FileRef
      location = "group:../ODataKit/ODataKit.xcodeproj">
   </FileRef>
</Workspace>
''')


if __name__ == '__main__':
    ids = topotext()
    simplenotes(ids)
    workspace()
    print('wrote TopoText.xcodeproj, Examples/SimpleNotes/SimpleNotes.xcodeproj, TopoText.xcworkspace')
