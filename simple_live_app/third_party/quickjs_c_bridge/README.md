# Desktop bridges for quickjs

Generates shared binaries libraries to be consumed by flutter_js on desktop platforms.

## Windows

* Creating Ninja Structure

Run in Developer Command Prompt for VS2019 in this project rootFolder:

First, prepare to target x64:

```
"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
```

Now generate the Ninja project:

**Release**

```bash
cmake -S .\windows -B build\windows -DCMAKE_BUILD_TYPE=Release -G "Ninja"
```

or 

**Debug**

```bash
cmake -S .\windows -B build\windows -G "Ninja"
```

Now compile using the ninja project generated:

```bash
cmake --build .\build\windows
```

### How to see symbols exported from a dll

```dumpbin.exe /exports build/windows/quickjs_c_bridge.dll```

## Linux

At the project root directory, run:

```bash
cmake -S ./linux -B ./build/linux
```

now build the library executing the command bellow:

```bash
cmake --build build/linux
```
## Windows References

* Build to Windows using CMake and Ninja Generator: https://dmerej.info/blog/post/cmake-visual-studio-and-the-command-line/
* How to build to Release: https://stackoverflow.com/a/7725055/5288244

## References

* https://dmerej.info/blog/post/cmake-visual-studio-and-the-command-line/
* https://devblogs.microsoft.com/cppblog/cmake-support-in-visual-studio/
* https://www.scivision.dev/cmake-install-windows/
* https://cmake.org/

https://github.com/jerson/flutter-openpgp/blob/master/scripts/upgrade_bridge_libs.sh
https://github.com/jerson?tab=repositories


https://github.com/jerson/flutter-rsa


https://github.com/jerson/openpgp-mobile/tree/master/proto

https://github.com/jerson/rsa-mobile/blob/master/Makefile

https://github.com/onelson/jq-rs

https://github.com/onelson/jq-sys

https://github.com/stedolan/jq

https://github.com/itchyny/gojq
