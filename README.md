# My Bucket for [Scoop](https://scoop.sh)
[![Tests](https://github.com/maoyeedy/yeedyscoop/actions/workflows/ci.yml/badge.svg)](https://github.com/maoyeedy/yeedyscoop/actions/workflows/ci.yml) [![Excavator](https://github.com/maoyeedy/yeedyscoop/actions/workflows/excavator.yml/badge.svg)](https://github.com/maoyeedy/yeedyscoop/actions/workflows/excavator.yml)

To start with:
```
scoop bucket add maoyeedy_scoop https://github.com/maoyeedy/scoop
```
To install a manifest from [bucket folder](bucket/):
```
scoop install $manifest
```
To manually update:
```
.\bin\checkver.ps1 -Update
```

To check github repo latest release:
```
https://api.github.com/repos/$UserName/$RepoName/releases/latest
```

To see json of a manifest:
```
scoop cat $manifest
```

### Manifests that I maintain:

#### CLI apps
- [FBX2glTF](bucket/FBX2glTF.json)
- [FbxFormatConverter](bucket/FbxFormatConverter.json)
- [cpz](bucket/cpz.json)
- [rmz](bucket/rmz.json)

#### GUI apps
- [blender-aliyun](bucket/blender-aliyun.json)
- [uu](bucket/uu.json)
- [leigod](bucket/leigod.json)
- [unity2022lts](bucket/unity2022lts.json)
- [window-centering-helper](bucket/window-centering-helper.json)
