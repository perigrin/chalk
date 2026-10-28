# ABOUTME: a die whose message may not end in a newline gets " at FILE line N."
# ABOUTME: appended, as perl's does -- from the site B::SoN records for it.
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


# The program at $pl through B::SoN, chalk's pipeline and lli: perl's message
# names the file it compiled, so both read the same one.
sub through_llvm_file ($pl) {
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

# Refused: "perl appends ' at FILE line N.'" (pvm 063 136).
for my $src (
    qq{eval { die "no newline" };\nprint "[\$@]";\n},
    qq{my \$g = \$ENV{X} // "a\\n";\neval { die(\$g) };\nprint "[\$@]";\n},
    qq{my \$g = \$ENV{X} // "a";\n\neval { die \$g, "b" };\nprint "[\$@]";\n},
    qq{eval { die "" };\nprint "[\$@]";\n},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $want = qx($^X $pl 2>/dev/null);
    my $got = eval { through_llvm_file($pl) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
