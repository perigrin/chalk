# ABOUTME: Every test takes lli from Chalk::CodeGen::Harness::LLI: $ENV{LLI}, else /usr/bin/lli,
# ABOUTME: and LLVM 17 or later (chalk's runtime writes `ptr`); no test file names a path of its own.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Find;
use File::Temp qw(tempdir);

use Chalk::CodeGen::Harness::LLI;
my $H = 'Chalk::CodeGen::Harness::LLI';

# A stand-in lli that says which LLVM it is.
my $dir = tempdir( CLEANUP => 1 );
sub fake_lli ($name, $version_text) {
    my $p = "$dir/$name";
    open my $fh, '>', $p or die "$p: $!";
    print $fh "#!/bin/sh\ncat <<'EOT'\n$version_text\nEOT\n";
    close $fh;
    chmod 0755, $p;
    return $p;
}
my $lli15 = fake_lli( 'lli15', "Ubuntu LLVM version 15.0.7\n  Optimized build." );
my $lli17 = fake_lli( 'lli17', "LLVM (http://llvm.org/):\n  LLVM version 17.0.6\n  Optimized build." );
my $lli18 = fake_lli( 'lli18', "Ubuntu LLVM version 18.1.3\n  Optimized build." );
my $junk  = fake_lli( 'junk',  "hello" );

# THE PATH: $ENV{LLI}, else /usr/bin/lli.
{
    local $ENV{LLI};
    delete $ENV{LLI};
    is( $H->path, '/usr/bin/lli', 'no LLI set: /usr/bin/lli' );
    local $ENV{LLI} = $lli18;
    is( $H->path, $lli18, 'LLI set: that path' );
}

# THE VERSION: 17 or later, and the reason says what was found.
{
    local $ENV{LLI} = $lli18;
    is( $H->skip_reason, undef, 'LLVM 18: usable' );
    is( $H->version, 18, 'LLVM 18: its major version' );
    local $ENV{LLI} = $lli17;
    is( $H->skip_reason, undef, 'LLVM 17: usable' );
    local $ENV{LLI} = $lli15;
    like( $H->skip_reason, qr/LLVM 15.*17 or later.*set LLI/s, 'LLVM 15: refused, by version' );
    like( $H->skip_reason, qr/\Q$lli15\E/, 'LLVM 15: the reason names the path' );
    local $ENV{LLI} = "$dir/none";
    like( $H->skip_reason, qr/lli not found at \Q$dir\E\/none.*set LLI/s, 'no such file: not found' );
    local $ENV{LLI} = $junk;
    like( $H->skip_reason, qr/does not say which LLVM/, 'a program that names no version: refused' );
}

# lli: the path, or the whole test file is skipped with that reason.
{
    my $run = sub ($lli) {
        local $ENV{LLI} = $lli;
        return scalar qx($^X -Ilib -It/lib -MChalk::CodeGen::Harness::LLI -e 'print "got ", Chalk::CodeGen::Harness::LLI->lli, "\n"' 2>&1);
    };
    is( $run->($lli18), "got $lli18\n", 'lli: a usable one is returned' );
    like( $run->($lli15), qr/\A1\.\.0 # SKIP .*LLVM 15/, 'lli: LLVM 15 skips the whole file' );
    is( $? >> 8, 0, 'lli: and a skip is not a failure' );
    unlike( $run->($lli15), qr/got/, 'lli: nothing runs after the skip' );
}

# A SIBLING TOOL (llvm-as) is the one beside lli, so it is the same LLVM.
{
    local $ENV{LLI};
    delete $ENV{LLI};
  SKIP: {
        skip 'no /usr/bin/lli here', 1 unless -x '/usr/bin/lli';
        like( $H->tool('llvm-as'), qr{/llvm-as\z}, 'tool: llvm-as beside lli' );
    }
}

# NO FILE under t/ or tools/ names an lli of its own.
{
    my @own;
    find( { no_chdir => 1, wanted => sub {
        return unless -f $_ && /\.(?:t|pm|pl|sh)\z/;
        my $file = $File::Find::name;
        return if $file eq 't/lib/Chalk/CodeGen/Harness/LLI.pm' || $file eq 't/bootstrap/lli-is-taken-from-one-place.t';
        open my $fh, '<', $file or die "$file: $!";
        while ( my $line = <$fh> ) {
            push @own, "$file:$.: $line" if $line =~ m{llvm-\d+/bin|\$ENV\{LLI\}|/usr/bin/lli\b|/usr/bin/llvm-as\b};
        }
    } }, 't', 'tools' );
    is( scalar @own, 0, 'no file names an lli path or reads $ENV{LLI} itself' ) or diag join '', @own[ 0 .. ( $#own < 20 ? $#own : 20 ) ];
}

done_testing;
