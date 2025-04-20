# Maoyeedy's [Scoop](https://scoop.sh) Bucket

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/Maoyeedy/Scoop/ci.yml?branch=master&label=Tests&style=flat-square)](https://github.com/Maoyeedy/Scoop/actions/workflows/ci.yml)  [![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/Maoyeedy/Scoop/excavator.yml?branch=master&label=Excavator&style=flat-square)](https://github.com/Maoyeedy/Scoop/actions/workflows/excavator.yml)  [![License](https://img.shields.io/github/license/Maoyeedy/Scoop?label=License&style=flat-square)](https://github.com/Maoyeedy/Scoop/blob/master/LICENSE)  [![Target-Windows](https://img.shields.io/badge/Target-Windows-blue?style=flat-square)](https://www.microsoft.com/en-us/windows)  [![GitHub repo size](https://img.shields.io/github/repo-size/Maoyeedy/Scoop?style=flat-square)](https://github.com/Maoyeedy/Scoop)

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
- [FBX2glTF](./bucket/FBX2glTF.json)
- [FbxFormatConverter](./bucket/FbxFormatConverter.json)
- [cpz](./bucket/cpz.json)
- [rmz](./bucket/rmz.json)
- [ptr](./bucket/ptr.json)
- [minhtml](./bucket/minhtml.json)

#### GUI apps
- [unity2022lts](./bucket/unity2022lts.json)
- [unity6000lts](./bucket/unity6000lts.json)
- [blender-aliyun](./bucket/blender-aliyun.json)
- [uu](./bucket/uu.json)
- [leigod](./bucket/leigod.json)
- [window-centering-helper](./bucket/window-centering-helper.json)
- [ChineseSubFinder](./bucket/chinesesubfinder.json)

If you experience any issues with above manifests, Issues and Pull Requests are welcome!
