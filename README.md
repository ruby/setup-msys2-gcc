# setup-msys2-gcc

This repo creates three prepackaged MSYS2 7z files for use with GitHub Actions Windows images.
The packages are updated four times a day.

 The packages are downloaded and extracted by code in [ruby/setup-ruby](https://github.com/ruby/setup-ruby).

 The three packages are:

 **`msys2.7z`** The base msys2 installation on Actions Windows images contains a minimal
 set of bash tools, and no shared build tools.  Code updates the packages, and saves only
 updated files to the 7z.  All Ruby Windows releases from version 2.5 and later use these
 tools.

 **`mingw64.7z`** This contains the mingw64 gcc chain and any packages needed to build
 Ruby.  Normal Ruby Windows releases from version 2.4 thru 3.0 use these tools.

 **`ucrt64.7z`** This contains the ucrt64 gcc chain and any packages needed to build
 Ruby.  Normal Ruby Windows releases from version 3.1 and later use these tools.
