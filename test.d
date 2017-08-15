module test;

import std.process;
import std.stdio;
import std.file;
import std.path;
import std.algorithm;
import std.string;
import std.exception;

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

        foreach (const clang ; matrix.clangs)
        {
            import std.string;

            activate(clang);

            auto output = execute(["./bin/dstep", "--clang-version"]);

            writeln("Testing with ", strip(output.output));
            result += unitTest();
            result += libraryTest();
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
        std.stdio.write("Activating clang ", clang.version_);

        version (Windows)
        {
            auto src = buildNormalizedPath(workingDirectory, clang.versionedLibclang);
            auto dest = buildNormalizedPath(workingDirectory, clang.libclang);

            if (exists(dest))
                remove(dest);

            copy(src, dest);

            auto staticSrc = buildNormalizedPath(workingDirectory, clang.staticVersionedLibclang);
            auto staticDest = buildNormalizedPath(workingDirectory, clang.staticLibclang);

            if (exists(staticDest))
                remove(staticDest);

            copy(staticSrc, staticDest);
        }
        else
        {
            execute(["./configure", "--llvm-path", clang.llvmLibPath]);
        }

        build();

        writeln(" [DONE]");
    }

    int unitTest ()
    {
        writeln("Running unit tests ");

        auto result = executeShell(dubShellCommand("test"));

        if (result.status != 0)
            writeln(result.output);

        return result.status;
    }

    /**
       Test that dstep can be used as a library by compiling a dependent
       dub package
     */
    int libraryTest ()
    {
        const string[string] env;
        const config = Config.none;
        const maxOutput = size_t.max;
        const workDir = "test_package";
        const result = executeShell(dubShellCommand("build"),
                                    env,
                                    config,
                                    maxOutput,
                                    workDir);
        if (result.status != 0)
            writeln(result.output);

        return result.status;
    }

    void build ()
    {
        try
        {
            auto result = executeShell(dubShellCommand("build"));

            if (result.status != 0)
            {
                writeln(result.output);
                throw new Exception("Failed to build DStep");
            }
        }
        catch(ProcessException)
        {
            throw new ProcessException("Failed to execute dub");
        }
    }
}


private string dubShellCommand(string subCommand) @safe pure nothrow
{
    return "dub " ~ subCommand ~ dubArch;
}

private string dubArch() @safe pure nothrow
{
    version (Windows)
    {
        version (X86_64)
            return " --arch=x86_64";
        else
            return " --arch=x86_mscoff";
    }
    else
    {
        return "";
    }
}

struct Clang
{
    string version_;
    string baseUrl;
    string filename;
    string basePath;

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
        enum staticExtension = ".lib";
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

    version (Windows)
    {
        string staticLibclang () const
        {
            return Clang.prefix ~ "clang" ~ Clang.staticExtension;
        }
    }

    string versionedLibclang () const
    {
        return Clang.prefix ~ "clang-" ~ version_ ~ Clang.extension;
    }

    version (Windows)
    {
        string staticVersionedLibclang () const
        {
            return Clang.prefix ~ "clang-" ~ version_ ~ Clang.staticExtension;
        }
    }

    string archivePath () const
    {
        return buildNormalizedPath(basePath, filename);
    }

    string extractionPath() const
    {
        version (Posix)
            return archivePath.stripExtension.stripExtension;
        else
            return buildNormalizedPath(basePath, "clang-" ~ version_);
    }

    string llvmLibPath() const
    {
        version (Posix)
            enum libPath = "lib";
        else
            enum libPath = "bin";

        return buildNormalizedPath(extractionPath, libPath);
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
        this.workingDirectory = workingDirectory;
        this.basePath = basePath;
        clangs = getClangs();
    }

    void downloadAll ()
    {
        mkdirRecurse(basePath);

        foreach (clang ; ClangMatrix.clangs)
        {
            stdout.flush();
            download(clang);
        }
    }

    void extractAll ()
    {
        foreach (clang ; ClangMatrix.clangs)
        {
            extractArchive(clang);
            extractLibclang(clang);
            extractStaticLibclang(clang);
            stdout.flush();
        }
    }

private:

    void download (const ref Clang clang)
    {
        import std.file : write;
        import HttpClient : getBinary;

        auto dest = clang.archivePath;

        if (exists(dest))
            return;

        auto url = clang.baseUrl ~ clang.filename;

        std.stdio.write("Downloading clang ", clang.version_);
        stdout.flush();
        write(dest, getBinary(url));
        writeln(" [DONE]");
    }

    void extractArchive (const ref Clang clang)
    {
        auto src = clang.archivePath;
        auto dest = clang.extractionPath;
        import std.stdio;
        writeln("extracting archive to ", dest);

        if (exists(dest))
            return;

        std.stdio.write("Extracting clang ", clang.version_);
        mkdirRecurse(dest);

        std.typecons.Tuple!(int, "status", string, "output") result;

        version (Posix)
        {
            result = execute(["tar", "--strip-components=1", "-C", dest, "-xf", src]);
        }
        else
        {
            try
            {
                result = execute(["7z", "x", src, "-y", format("-o%s", dest)]);
            }
            catch (ProcessException)
            {
                throw new ProcessException("Failed to execute 7z");
            }
        }

        if (result.status != 0)
            throw new ProcessException("Failed to extract archive");

        writeln(" [DONE]");
    }

    void extractLibclang (const ref Clang clang)
    {
        version (Windows)
        {
            auto src = buildNormalizedPath(clang.extractionPath, "bin", clang.libclang);
            auto dest = buildNormalizedPath(workingDirectory, clang.versionedLibclang);

            stdout.flush();

            copy(src, dest);
        }
    }

    void extractStaticLibclang (const ref Clang clang)
    {
        version (Windows)
        {
            auto src = buildNormalizedPath(clang.extractionPath, "lib", clang.staticLibclang);
            auto dest = buildNormalizedPath(workingDirectory, clang.staticVersionedLibclang);
            import std.stdio;
            writeln("Extracting static libclang to ", dest);

            stdout.flush();

            copy(src, dest);
        }
    }

    Clang clang(string version_, string baseUrl, string filename)
    {
        return Clang(version_, baseUrl, filename, basePath);
    }

    immutable(Clang[]) getClangs ()
    {
        version (Posix)
            void unsupported()
            {
                throw new Exception("Current version of '" ~ System.update ~ "' is not supported");
            }

        version (FreeBSD)
        {
            version (D_LP64)
                return [
                    clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-amd64-unknown-freebsd10.tar.xz"),
                    clang("3.9.1", "http://releases.llvm.org/3.9.1/", "clang+llvm-3.9.1-amd64-unknown-freebsd10.tar.xz"),
                    clang("4.0.0", "http://releases.llvm.org/4.0.0/", "clang+llvm-4.0.0-amd64-unknown-freebsd10.tar.xz")
                ];

            else
                return [
                    clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-i386-unknown-freebsd10.tar.xz"),
                    clang("3.9.1", "http://releases.llvm.org/3.9.1/", "clang+llvm-3.9.1-i386-unknown-freebsd10.tar.xz"),
                    clang("4.0.0", "http://releases.llvm.org/4.0.0/", "clang+llvm-4.0.0-i386-unknown-freebsd10.tar.xz")
                ];
        }

        else version (linux)
        {
            if (System.isUbuntu || System.isTravis)
            {
                version (D_LP64)
                    return [
                        clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz"),
                        clang("3.9.1", "http://releases.llvm.org/3.9.1/", "clang+llvm-3.9.1-x86_64-linux-gnu-ubuntu-14.04.tar.xz"),
                        clang("4.0.0", "http://releases.llvm.org/4.0.0/", "clang+llvm-4.0.0-x86_64-linux-gnu-ubuntu-14.04.tar.xz")
                    ];
                else
                    unsupported();
            }

            else if (System.isDebian)
            {
                version (D_LP64)
                    return [
                        clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-x86_64-linux-gnu-debian8.tar.xz"),
                        clang("3.9.1", "http://releases.llvm.org/3.9.1/", "clang+llvm-3.9.1-x86_64-linux-gnu-debian8.tar.xz"),
                        clang("4.0.0", "http://releases.llvm.org/4.0.0/", "clang+llvm-4.0.0-x86_64-linux-gnu-debian8.tar.xz")
                    ];
                else
                    unsupported();
            }

            else if (System.isFedora)
            {
                version (D_LP64)
                    return [
                        clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-x86_64-fedora23.tar.xz")
                    ];
                else
                    return [
                        clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-i686-fedora23.tar.xz")
                    ];
            }

            else
                unsupported();

            return null;
        }

        else version (OSX)
        {
            version (D_LP64)
            {
                return [
                    clang("3.9.0", "http://releases.llvm.org/3.9.0/", "clang+llvm-3.9.0-x86_64-apple-darwin.tar.xz"),
                    clang("4.0.0", "http://releases.llvm.org/4.0.0/", "clang+llvm-4.0.0-x86_64-apple-darwin.tar.xz")
                ];
            }

            else
                static assert(false, "Only 64bit versions of OS X are supported");
        }

        else version (Win32)
        {
            return [
                clang("3.9.0", "http://releases.llvm.org/3.9.0/", "LLVM-3.9.0-win32.exe"),
                clang("3.9.1", "http://releases.llvm.org/3.9.1/", "LLVM-3.9.1-win32.exe"),
                clang("4.0.0", "http://releases.llvm.org/4.0.0/", "LLVM-4.0.0-win32.exe")
            ];
        }

        else version (Win64)
        {
            return [
                clang("3.9.0", "http://releases.llvm.org/3.9.0/", "LLVM-3.9.0-win64.exe"),
                clang("3.9.1", "http://releases.llvm.org/3.9.1/", "LLVM-3.9.1-win64.exe"),
                clang("4.0.0", "http://releases.llvm.org/4.0.0/", "LLVM-4.0.0-win64.exe")
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

version (Posix):

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
