module test;

import std.process;
import std.stdio;
import std.file;
import std.path;
import std.algorithm;
import std.string;
import std.exception;

alias println = writeln;

int main ()
{
    return TestRunner().run;
}

struct TestRunner
{
    private string wd;

    int run ()
    {
        int result = 0;
        auto matrix = setup();
        activate(matrix.clangs[0]);
        build();

        foreach (const clang ; matrix.clangs)
        {
            import std.string;

            activate(clang);

            auto output = execute(["./bin/dstep", "--clang-version"]);

            writeln("Testing with ", strip(output.output));
            result += unitTest();
            stdout.flush();
        }

        return result;
    }

    string workingDirectory ()
    {
        if (wd.length)
            return wd;

        return wd = getcwd();
    }

    auto setup ()
    {
        auto matrix = ClangMatrix(workingDirectory, clangBasePath);
        matrix.downloadAll;
        matrix.extractAll;

        return matrix;
    }

    string clangBasePath ()
    {
        return buildNormalizedPath(workingDirectory, "clangs");
    }

    void activate (const Clang clang)
    {
        auto src = buildNormalizedPath(workingDirectory, clang.versionedLibclang);
        auto dest = buildNormalizedPath(workingDirectory, clang.libclang);
println("src: ", src, " dest: ", dest, " src exists: ", src.exists, " dest exists: ", dest.exists);
        if (exists(dest))
            remove(dest);

        copy(src, dest);
    }

    int unitTest ()
    {
        writeln("Running unit tests ");

        version (Win64)
            auto result = executeShell("dub test --arch=x86_64");
        else
            auto result = executeShell("dub test");

        if (result.status != 0)
            writeln(result.output);

        return result.status;
    }

    void build ()
    {
        version (Win64)
            auto result = executeShell("dub build --arch=x86_64");
        else
            auto result = executeShell("dub build");

        if (result.status != 0)
        {
            writeln(result.output);
            throw new Exception("Failed to build DStep");
        }
    }
}

struct Clang
{
    string version_;
    string baseUrl;
    string filename;

    version (linux)
    {
        enum extension = ".so";
        enum prefix = "lib";
    }

    else version (OSX)
    {
        enum extension = ".dylib";
        enum prefix = "lib";
    }

    else version (Windows)
    {
        enum extension = ".dll";
        enum prefix = "lib";
    }

    else version (FreeBSD)
    {
        enum extension = ".so";
        enum prefix = "lib";
    }

    else
        static assert(false, "Unsupported platform");

    string libclang () const
    {
        return Clang.prefix ~ "clang" ~ Clang.extension;
    }

    string versionedLibclang () const
    {
        return Clang.prefix ~ "clang-" ~ version_ ~ Clang.extension;
    }
}

struct ClangMatrix
{
    private
    {
        string basePath;
        string workingDirectory;
        string clangPath_;
        immutable Clang[] clangs;
    }


    this (string workingDirectory, string basePath)
    {
        clangs = getClangs();
        this.workingDirectory = workingDirectory;
        this.basePath = basePath;
    }

    void downloadAll ()
    {
        foreach (clang ; ClangMatrix.clangs)
        {
            if (libclangExists(clang))
                continue;

            writeln("Downloading clang ", clang.version_);
            mkdirRecurse(basePath);
            stdout.flush();
            download(clang);
        }
    }

    void extractAll ()
    {
        foreach (clang ; ClangMatrix.clangs)
        {
            if (libclangExists(clang))
                continue;

            writeln("Extracting clang ", clang.version_);
            extractArchive(clang);
            extractLibclang(clang);
            stdout.flush();
            clean();
        }
    }

private:

    bool libclangExists (const ref Clang clang)
    {
        auto libclangPath = buildNormalizedPath(workingDirectory, clang.versionedLibclang);
        return exists(libclangPath);
    }

    void download (const ref Clang clang)
    {
        auto url = clang.baseUrl ~ clang.filename;
        auto dest = archivePath(clang.filename);

        import std.file : write;
        import HttpClient : getBinary;

        if (!exists(dest))
            write(dest, getBinary(url));
    }

    void extractArchive (const ref Clang clang)
    {
        auto src = archivePath(clang.filename);
        auto dest = clangPath();
        println("extractionPath - src: ", src, " dest: ", dest);
        mkdirRecurse(dest);

        version (Posix)
            auto result = execute(["tar", "--strip-components=1", "-C", dest, "-xf", src]);
        else
            auto result = execute(["7z", "x", src, "-y", format("-o%s", dest)]);

        if (result.status != 0)
            throw new ProcessException("Failed to extract archive");
    }

    string archivePath (string filename)
    {
        return buildNormalizedPath(basePath, filename);
    }

    string clangPath ()
    {
        if (clangPath_.length)
            return clangPath_;

        return clangPath_ = buildNormalizedPath(basePath, "clang");
    }

    void extractLibclang (const ref Clang clang)
    {
        version (Posix)
            auto src = buildNormalizedPath(clangPath, "lib", clang.libclang);
        else
            auto src = buildNormalizedPath(clangPath, "bin", clang.libclang);

        auto dest = buildNormalizedPath(workingDirectory, clang.versionedLibclang);

        copy(src, dest);
    }

    void clean ()
    {
        rmdirRecurse(clangPath);
    }

    immutable(Clang[]) getClangs ()
    {
        version (FreeBSD)
        {
            version (D_LP64)
                return [
                    // Clang("3.7.1", "http://llvm.org/releases/3.7.1/", "clang+llvm-3.7.1-amd64-unknown-freebsd10.tar.xz"),
                    // Clang("3.7.0", "http://llvm.org/releases/3.7.0/", "clang+llvm-3.7.0-amd64-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.2", "http://llvm.org/releases/3.6.2/", "clang+llvm-3.6.2-amd64-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.1", "http://llvm.org/releases/3.6.1/", "clang+llvm-3.6.1-amd64-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.0", "http://llvm.org/releases/3.6.0/", "clang+llvm-3.6.0-amd64-unknown-freebsd10.tar.xz"),
                    // Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-amd64-unknown-freebsd10.tar.xz"),
                    Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-amd64-unknown-freebsd9.2.tar.xz"),
                ];

            else
                return [
                    // Clang("3.7.1", "http://llvm.org/releases/3.7.1/", "clang+llvm-3.7.1-i386-unknown-freebsd10.tar.xz"),
                    // Clang("3.7.0", "http://llvm.org/releases/3.7.1/", "clang+llvm-3.7.0-i386-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.2", "http://llvm.org/releases/3.6.2/", "clang+llvm-3.6.2-i386-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.1", "http://llvm.org/releases/3.6.1/", "clang+llvm-3.6.1-i386-unknown-freebsd10.tar.xz"),
                    // Clang("3.6.0", "http://llvm.org/releases/3.6.0/", "clang+llvm-3.6.0-i386-unknown-freebsd10.tar.xz"),
                    // Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-i386-unknown-freebsd10.tar.xz"),
                    Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-i386-unknown-freebsd9.2.tar.xz"),
                ];
        }

        else version (linux)
        {
            if (System.isTravis)
            {
                return [
                    // Clang("3.5.1", "http://llvm.org/releases/3.5.1/", "clang+llvm-3.5.1-x86_64-linux-gnu.tar.xz"),
                    // Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz"),
                    Clang("3.4.2", "http://llvm.org/releases/3.4.2/", "clang+llvm-3.4.2-x86_64-unknown-ubuntu12.04.xz"),
                    Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "clang+llvm-3.4.1-x86_64-unknown-ubuntu12.04.tar.xz"),
                    Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-x86_64-unknown-ubuntu12.04.tar.xz"),
                ];
            }

            else if (System.isUbuntu)
            {
                version (D_LP64)
                    return [
                        Clang("3.5.1", "http://llvm.org/releases/3.5.1/", "clang+llvm-3.5.1-x86_64-linux-gnu.tar.xz"),
                        Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz"),
                        Clang("3.4.2", "http://llvm.org/releases/3.4.2/", "clang+llvm-3.4.2-x86_64-unknown-ubuntu12.04.xz"),
                        Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "clang+llvm-3.4.1-x86_64-unknown-ubuntu12.04.tar.xz"),
                        Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-x86_64-unknown-ubuntu12.04.tar.xz"),
                    ];
                else
                    return [
                    ];
            }

            else if (System.isDebian)
            {
                version (D_LP64)
                    return [
                    ];
                else
                    return [
                    ];

            }

            else if (System.isFedora)
            {
                version (D_LP64)
                    return [
                        Clang("3.5.1", "http://llvm.org/releases/3.5.1/", "clang+llvm-3.5.1-x86_64-fedora20.tar.xz"),
                        Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-x86_64-fedora20.tar.xz"),
                        Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-x86_64-fedora19.tar.gz"),
                    ];
                else
                    return [
                        Clang("3.5.1", "http://llvm.org/releases/3.5.1/", "clang+llvm-3.5.1-i686-fedora20.tar.xz"),
                        Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-i686-fedora20.tar.xz"),
                        Clang("3.4.2", "http://llvm.org/releases/3.4.2/", "clang+llvm-3.4.2-i686-fedora20.xz"),
                        Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "clang+llvm-3.4.1-i686-fedora20.tar.xz"),
                        Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-i686-fedora19.tar.gz"),
                    ];
            }

            else
                throw new Exception("Current Linux distribution '" ~ System.update ~ "' is not supported");
        }

        else version (OSX)
        {
            version (D_LP64)
            {
                if (System.isTravis)
                    return [
                        Clang("3.7.0", "http://llvm.org/releases/3.7.0/", "clang+llvm-3.7.0-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.2", "http://llvm.org/releases/3.6.2/", "clang+llvm-3.6.2-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.1", "http://llvm.org/releases/3.6.1/", "clang+llvm-3.6.1-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.0", "http://llvm.org/releases/3.6.0/", "clang+llvm-3.6.0-x86_64-apple-darwin.tar.xz"),
                        Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-macosx-apple-darwin.tar.xz"),
                        // Clang("3.4.2", "http://llvm.org/releases/3.4.2/", "clang+llvm-3.4.2-x86_64-apple-darwin10.9.xz"),
                        // Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "clang+llvm-3.4.1-x86_64-apple-darwin10.9.tar.xz"),
                        // Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-x86_64-apple-darwin10.9.tar.gz"),
                    ];

                else
                    return [
                        Clang("3.7.0", "http://llvm.org/releases/3.7.0/", "clang+llvm-3.7.0-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.2", "http://llvm.org/releases/3.6.2/", "clang+llvm-3.6.2-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.1", "http://llvm.org/releases/3.6.1/", "clang+llvm-3.6.1-x86_64-apple-darwin.tar.xz"),
                        Clang("3.6.0", "http://llvm.org/releases/3.6.0/", "clang+llvm-3.6.0-x86_64-apple-darwin.tar.xz"),
                        Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "clang+llvm-3.5.0-macosx-apple-darwin.tar.xz"),
                        Clang("3.4.2", "http://llvm.org/releases/3.4.2/", "clang+llvm-3.4.2-x86_64-apple-darwin10.9.xz"),
                        // Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "clang+llvm-3.4.1-x86_64-apple-darwin10.9.tar.xz"),
                        // Clang("3.4", "http://llvm.org/releases/3.4/", "clang+llvm-3.4-x86_64-apple-darwin10.9.tar.gz"),
                    ];
            }

            else
                static assert(false, "Only 64bit versions of OS X are supported");
        }

        else version (Win32)
        {
            return [
                // Clang("3.8.1", "http://llvm.org/releases/3.8.1/", "LLVM-3.8.1-win32.exe"),
                Clang("3.8.0", "http://llvm.org/releases/3.8.0/", "LLVM-3.8.0-win32.exe"),
                // Clang("3.7.1", "http://llvm.org/releases/3.7.1/", "LLVM-3.7.1-win32.exe"),
                Clang("3.7.0", "http://llvm.org/releases/3.7.0/", "LLVM-3.7.0-win32.exe"),
                // Clang("3.6.2", "http://llvm.org/releases/3.6.2/", "LLVM-3.6.2-win32.exe"),
                // Clang("3.6.1", "http://llvm.org/releases/3.6.1/", "LLVM-3.6.1-win32.exe"),
                Clang("3.6.0", "http://llvm.org/releases/3.6.0/", "LLVM-3.6.0-win32.exe"),
                Clang("3.5.0", "http://llvm.org/releases/3.5.0/", "LLVM-3.5.0-win32.exe"),
                // Clang("3.4.1", "http://llvm.org/releases/3.4.1/", "LLVM-3.4.1-win32.exe"),
                Clang("3.4", "http://llvm.org/releases/3.4/", "LLVM-3.4-win32.exe")
            ];
        }

        else version (Win64)
        {
            return [
                Clang("3.8.0", "http://llvm.org/releases/3.8.0/", "LLVM-3.8.0-win64.exe"),
                Clang("3.7.0", "http://llvm.org/releases/3.7.0/", "LLVM-3.7.0-win64.exe"),
            ];
        }

        else
            static assert(false, "Unsupported platform");
    }
}

struct System
{
static:

    version (D_LP64)
        bool isTravis ()
        {
            return environment.get("TRAVIS", "false") == "true";
        }

    else
        bool isTravis ()
        {
            return false;
        }

version (linux):

    import core.sys.posix.sys.utsname;

    private
    {
        utsname data_;
        string update_;
        string nodename_;
    }

    bool isFedora ()
    {
        return nodename.canFind("fedora");
    }

    bool isUbuntu ()
    {
        return nodename.canFind("ubuntu") || update.canFind("ubuntu");
    }

    bool isDebian ()
    {
        return nodename.canFind("debian");
    }

    private utsname data()
    {
        import std.exception;

        if (data_ != data_.init)
            return data_;

        errnoEnforce(!uname(&data_));
        return data_;
    }

    string update ()
    {
        if (update_.length)
            return update_;

        return update_ = data.update.ptr.fromStringz.toLower.assumeUnique;
    }

    string nodename ()
    {
        if (nodename_.length)
            return nodename_;

        return nodename_ = data.nodename.ptr.fromStringz.toLower.assumeUnique;
    }
}
