# setup-msys2-gcc

[![Build](https://github.com/ruby/setup-msys2-gcc/actions/workflows/build.yml/badge.svg)](https://github.com/ruby/setup-msys2-gcc/actions/workflows/build.yml)

This repo packages the build tools needed to compile c and c++ source when using Windows
Rubies with GitHub Actions.

## Release Assets

| Name                                  | Used by Ruby    |
|---------------------------------------|-----------------|
| `msys2-clangarm64.7z`                 | `>= 3.4`        |
| `msys2-mingw64-gcc@14-openssl@1.1.7z` | `>= 2.4, < 3.1` |
| `msys2-mingw64.7z`                    |                 |
| `msys2-ucrt64-gcc@14-openssl@1.1.7z`  | `>= 3.1, < 3.2` |
| `msys2-ucrt64-gcc@14.7z`              | `>= 3.2, < 3.5` |
| `msys2-ucrt64.7z`                     | `>= 3.5`        |
| `vcpkg-arm64-windows.7z`              | `mswin`         |
| `vcpkg-x64-windows.7z`                | `mswin`         |

The code installs the MSYS2 and vcpkg packages with GitHub Actions.  If any packages have been
updated since the latest release, it creates a new release and uploads all packages.

## Dependency Pinning

### MSYS2

> [!NOTE]
> Installed packages are archived in `msys2-*-var-cache-pacman-pkg.7z` in case downgrade is needed.

If a specific version of a dependency is needed:

- Upload packages to [msys2-packages](https://github.com/ruby/setup-msys2-gcc/releases/tag/msys2-packages).
- Update `msys2-extra` matrix job.
- Update [ruby/setup-ruby](https://github.com/ruby/setup-ruby) if needed.

### vcpkg

If a specific version of a dependency is needed:

- Update `vcpkg.json` defined in the `vcpkg` matrix job.
- Update [ruby/setup-ruby](https://github.com/ruby/setup-ruby) if needed.
