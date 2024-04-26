# setup-msys2-gcc

### Purpose

This repo packages the build tools needed to compile c and c++ source when using Windows
Rubies with GitHub Actions.

### General

Publicly available Windows Rubies are built with the [MSYS2](https://github.com/msys2) system,
which provides a bash shell, compilers and tools, and various packages.  Windows Rubies 2.4 thru 
3.0 use the MSYS2 tools refered to as 'mingw64', which compile using legacy Windows libraries.
Windows Rubies 3.1 and later use 'ucrt64', which use newer Windows libraries.

Below summarizes the default MSYS2 installations on Actions Windows images:

| Actions<br/>Image  |  MSYS<br/>Base | MSYS<br/>Build Tools | mingw64<br/>gcc & tools | mingw64<br/>packages | ucrt64<br/>gcc & tools | ucrt64<br/>packages |
|--------------------|:--------------:|:--------------------:|:-----------------------:|:--------------------:|:----------------------:|:-------------------:|
| **2022 and later** | Yes | No  | No  | No  | No  | No |
| **2016, 2019**     | Yes | Yes | Yes | Some | No  | No  |

### Notes

Six package files are stored in a GitHub release, and are used by
[ruby/setup-ruby](https://github.com/ruby/setup-ruby).  They are:

* **`msys2.7z`** The base msys2 installation on Actions Windows images contains a minimal
set of bash tools, and no shared build tools.  Code updates the MSYS2 files, and saves only
updated files to the 7z.  All Ruby Windows releases from version 2.4 and later use these
tools.

* **`mingw64.7z`** This contains the mingw64 gcc chain and any packages needed to build
Ruby.  This has OpenSSL 1.1.1 installed, as of 26-Apr-2024, 1.1.1.w.  Normal Ruby Windows
releases from version 2.4 thru 3.0 use these tools.

* **`mingw64-3.0.7z`** This contains the mingw64 gcc chain and any packages needed to build
Ruby.  The MSYS2 OpenSSL 3.3.z package is installed.  The mingw Ruby master build is the
only build that uses this.

* **`ucrt64.7z`** This contains the ucrt64 gcc chain and any packages needed to build
Ruby.  This has OpenSSL 1.1.1 installed, as of 26-Apr-2024, 1.1.1.w.  Ruby version 3.1 is
the only release that uses this.

* **`ucrt64-3.0.7z`** This contains the ucrt64 gcc chain and any packages needed to build
Ruby. The MSYS2 OpenSSL 3.3.z package is installed.  Ruby 3.2, head, & ucrt builds use this.

* **`mswin.7z`** This contains files needed to compile Windows Ruby mswin builds. It contains
libffi, libyaml, openssl, readline, and zlib, built with the Microsoft vcpkg system.  This
contains OpenSSL 3.0.z.

The code installs the packages with [ruby/setup-ruby](https://github.com/ruby/setup-ruby),
then updates the MSYS2 and vcpkg packages.  If any packages have been updated, it creates
a new 7z file and updates the package in the release.
