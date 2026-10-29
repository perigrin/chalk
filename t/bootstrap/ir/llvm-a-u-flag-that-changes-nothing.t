# ABOUTME: a regex under `use v5.36` (unicode_strings: the u flag) whose pattern has no
# ABOUTME: class u changes (\w \s \d, POSIX, /i) matches as without it; one with one is refused.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $LLI = $ENV{LLI} // '/usr/lib/llvm-15/bin/lli';
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => "lli not found at $LLI (set LLI)"                  unless -x $LLI;

require Chalk::CodeGen::Pipeline;

# The whole program through B::SoN, chalk's pipeline and lli; its stdout.
sub through_llvm ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $json = qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) =
        Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $lf $units->[0]{ll};
    close $lf;
    my $out = qx($LLI $ll 2>&1);
    die "lli exited " . ($? >> 8) . ": $out" if $?;
    return $out;
}

sub perl_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return scalar qx($^X $pl 2>&1);
}

# pvm 112's s/1/9/, and a match, under use v5.36.
for my $src (
    qq{use v5.36;\nmy \$s = \$ENV{X} // "a1";\nprint \$s =~ /1/ ? "y" : "n", "\\n";\n},
    qq{use v5.36;\nmy \$s = \$ENV{X} // "a1b1";\n\$s =~ s/1/9/;\nprint "\$s\\n";\n},
) {
    my $got = eval { through_llvm($src) };
    is($got, perl_of($src), "perl's answer: " . ( $src =~ s/\n/ /gr )) or diag $@;
}

# \w under u matches a byte past ASCII that it does not without: refused.
{
    my $src = qq{use v5.36;\nmy \$s = \$ENV{X} // "a";\nprint \$s =~ /\\w/ ? "y" : "n", "\\n";\n};
    my $err = do { local $@; eval { through_llvm($src) }; $@ };
    like($err, qr/GAP/, 'a \w under the u flag: refused');
}

done_testing;
