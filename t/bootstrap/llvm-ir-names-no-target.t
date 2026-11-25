#!/usr/bin/env perl
# ABOUTME: Guard (CLAUDE.md constraint 7): the LLVM IR chalk writes names no architecture
# ABOUTME: and no one libc's own names; each such name still there is listed.

use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Find;

# WHY. LLVM IR is the target so that chalk is tied to no machine: the IR names
# none, and whoever compiles it picks one. Text pasted from a compiler's output
# carries that compiler's machine with it ("target-cpu"="x86-64"), and lli on
# another reads a function so marked as having no floating point at all.

# A name that ties the IR to a machine or to one libc, and what it names.
my @TIED = (
    [ 'target-cpu'             => qr/"target-cpu"/ ],
    [ 'target-features'        => qr/"target-features"/ ],
    [ 'tune-cpu'               => qr/"tune-cpu"/ ],
    [ 'min-legal-vector-width' => qr/"min-legal-vector-width"/ ],    # (x86's alone)
    [ 'target triple'          => qr/\btarget\s+triple\b/ ],
    [ 'target datalayout'      => qr/\btarget\s+datalayout\b/ ],
    [ 'machine type'           => qr/\b(?:x86_fp80|ppc_fp128|x86_amx)\b/ ],
    [ 'assembly'               => qr/\bmodule\s+asm\b|\basm\s+(?:sideeffect|alignstack|inteldialect)\b/ ],
    [ 'machine intrinsic'      => qr/\@llvm\.(?:x86|aarch64|arm|riscv|ppc|wasm)\./ ],
    [ '__errno_location'       => qr/\b__errno_location\b/ ],        # glibc's (macOS: __error)
    [ '__jmp_buf_tag'          => qr/\b__jmp_buf_tag\b/ ],           # glibc's jmp_buf, in x86-64's layout
    [ '__sigset_t'             => qr/\b__sigset_t\b/ ],              # glibc's
    [ 'x86-64'                 => qr/\bx86[-_]64\b/ ],
);

# STILL THERE. Each entry is a file and a name in it; a file not listed here may
# hold none of them -- and the list only shrinks.
my %KNOWN = (
    # errno, jmp_buf and glob_t are the C library's ABI, which LLVM IR cannot
    # ask for: how chalk does without is not ruled on yet. ('x86-64' is
    # t2_glob's note of the glob_t layout it reads.)
    'lib/Chalk/Target/LLVM/Runtime.pm' => [qw(__errno_location __jmp_buf_tag __sigset_t x86-64)],
);

my %seen;    # "file name" => 1
find( { no_chdir => 1, wanted => sub {
    return unless /\.pm\z/;
    my $file = $File::Find::name;
    open my $fh, '<', $file or die "$file: $!";
    while ( my $line = <$fh> ) {
        for my $t (@TIED) { $seen{"$file $t->[0]"} //= $. if $line =~ $t->[1] }
    }
} }, 'lib/Chalk/Target/LLVM', 'lib/Chalk/Target/LLVM.pm' );

my %known = map { my $f = $_; map { ( "$f $_" => 1 ) } $KNOWN{$f}->@* } keys %KNOWN;
my @tied = grep { !$known{$_} } sort keys %seen;
is_deeply( \@tied, [], 'the LLVM IR chalk writes names no machine, and no one libc, but the listed ones' )
    or diag "tied to a target:\n" . join "\n", map { "  $_ (line $seen{$_})" } @tied;

# The list only shrinks: an entry that is gone is removed, not kept.
my @stale = grep { !$seen{$_} } sort keys %known;
is_deeply( \@stale, [], 'every listed name is still there (remove the ones that are not)' )
    or diag "no longer there:\n" . join "\n", map { "  $_" } @stale;

done_testing;
