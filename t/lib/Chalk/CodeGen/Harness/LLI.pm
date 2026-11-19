# ABOUTME: The one place a test learns which lli to run: $ENV{LLI}, else /usr/bin/lli, and it must
# ABOUTME: be LLVM 17 or later. A test file calls ->lli, which skips the whole file when there is none.
use v5.42.0;
use utf8;
use experimental 'class';

# WHY 17. chalk's runtime IR writes the opaque pointer type `ptr` beside typed
# pointers (`i8*`). LLVM 15 reads a module as one or the other and rejects the
# mix ("ptr type is only supported in opaque pointers mode"); LLVM 17 and later
# read every pointer type as `ptr`. So an older lli does not run chalk's
# output at all, and a test that ran it would fail for a reason that is not
# the test's.
#
# WHY ONE PLACE. Some 490 test files each spelled the path, most of them
# `/usr/lib/llvm-15/bin/lli`; the day the runtime outgrew LLVM 15, 65 files
# failed at once. t/bootstrap/lli-is-taken-from-one-place.t keeps a path from
# being written anywhere else.
class Chalk::CodeGen::Harness::LLI {
    my $DEFAULT     = '/usr/bin/lli';
    my $MIN_VERSION = 17;
    my %version_of;    # path => major version, or 0 when the program names none

    # path() -> the lli a test runs: $ENV{LLI}, else /usr/bin/lli. No check.
    sub path ($class) {
        return $ENV{LLI} // $DEFAULT;
    }

    # version() -> the major LLVM version of path(), 0 when it names none,
    # undef when there is no such program.
    sub version ($class) {
        my $lli = $class->path;
        return undef unless -x $lli && !-d $lli;
        return $version_of{$lli} //= do {
            my $text = qx("$lli" --version 2>&1) // '';
            $text =~ /LLVM version (\d+)/ ? $1 + 0 : 0;
        };
    }

    # skip_reason() -> undef when path() is an lli chalk's output runs under,
    # else the sentence a skip gives.
    sub skip_reason ($class) {
        my $lli     = $class->path;
        my $version = $class->version;
        return "lli not found at $lli (set LLI to an lli of LLVM $MIN_VERSION or later)" unless defined $version;
        return "$lli does not say which LLVM it is (set LLI to an lli of LLVM $MIN_VERSION or later)" unless $version;
        return "$lli is LLVM $version; chalk's runtime needs LLVM $MIN_VERSION or later (set LLI)"
            if $version < $MIN_VERSION;
        return undef;
    }

    # lli() -> path(), for a test file that cannot run without it: when there
    # is no usable lli the whole file is skipped, here, with the reason. Call
    # it before the first test runs.
    sub lli ($class) {
        my $why = $class->skip_reason;
        return $class->path unless defined $why;
        print "1..0 # SKIP $why\n";
        exit 0;
    }

    # tool($name) -> the LLVM tool of that name beside lli (llvm-as, opt), so
    # it is the same LLVM. The link /usr/bin/lli is followed to its bin/.
    sub tool ($class, $name) {
        my $lli = $class->path;
        my ($dir) = $lli =~ m{\A(.*)/[^/]+\z};
        my $beside = defined $dir ? "$dir/$name" : $name;
        return $beside if -x $beside;
        my $real = readlink $lli;
        return $beside unless defined $real;
        $real = "$dir/$real" unless $real =~ m{\A/};
        my ($real_dir) = $real =~ m{\A(.*)/[^/]+\z};
        return "$real_dir/$name";
    }
}

1;
