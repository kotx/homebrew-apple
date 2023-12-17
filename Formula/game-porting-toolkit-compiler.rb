# Copyright (C) 2023 Apple, Inc.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
# documentation files (the “Software”), to deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
# Software.
# 
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class GamePortingToolkitCompiler < Formula
  version "0.2"
  desc "Compiler for Apple Game Porting Toolkit"
  homepage "https://developer.apple.com/"
  url "https://media.codeweavers.com/pub/crossover/source/crossover-sources-23.7.1.tar.gz", using: :nounzip
  sha256 "aa85487b0c80c97a0ddb8a8b9aaab1a720772af275af92d9997dded2bd15bf15"
  # license ""
  
  depends_on "cmake" => :build
  depends_on "ninja" => :build
  
  keg_only :provided_by_macos
  
  def install
    # Extract it ourselves, this lets us restrict extraction to just the clang directory.
    system "tar", "-xf", "crossover-sources-23.7.1.tar.gz", "--include=sources/clang/*", "--strip-components=2"
    
    mkdir "clang-build" do
      # Build an x86_64-native clang.
      system "cmake", "-G", "Ninja",
                      "-DCMAKE_VERBOSE_MAKEFILE=#{verbose? ? "On" : "Off"}",
                      "-DCMAKE_INSTALL_PREFIX=#{prefix}",
                      "-DCMAKE_MAKE_PROGRAM=ninja",
                      "-DCMAKE_BUILD_TYPE=Release",
                      "-DCMAKE_VERBOSE_MAKEFILE=On",
                      "-DCMAKE_OSX_ARCHITECTURES=x86_64",
                      "-DLLVM_TARGETS_TO_BUILD=X86",
                      "-DLLVM_NATIVE_ARCH=X86",
                      "-DLLVM_HOST_TRIPLE=x86_64-apple-darwin",
                      "-DLLVM_INSTALL_TOOLCHAIN_ONLY=On",
                      "-DLLVM_ENABLE_PROJECTS=clang",
                      buildpath/"llvm"
                      
        if verbose?
          system "ninja", "-v", "install"
        else
          system "ninja", "install"
        end
      end
      
    # Sometimes Wine tries to build with GCC even if it can find clang.
    bin.install_symlink "clang" => "gcc"
  end
end
