# ABOUTME: a division by zero in a block eval's body is that eval's die, with
# ABOUTME: perl's message naming the file and line B::SoN records for it.
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

# Refused: "a block eval whose body makes a value that may die" (pvm 062).
for my $src (
    qq{my \$d = \$ENV{X} // 0;\nmy \$r = eval { 10 / \$d } // "trapped";\nprint "\$r\\n";\n},
    qq{my \$d = \$ENV{X} // 0;\nmy \$r = eval { 10 / \$d };\nprint defined \$r ? "d" : "u", " [\$@]";\n},
    qq{my \$d = \$ENV{X} // 0;\nmy \$r = eval { 10 % \$d };\nprint "[\$@]";\n},
    qq{my \$d = \$ENV{X} // 2;\nmy \$r = eval { 10 / \$d };\nprint "\$r [\$@]\\n";\n},
) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    my $want = qx($^X $pl 2>/dev/null);
    my $got = eval { through_llvm_file($pl) };
    is($got, $want, "perl's answer for $src") or diag $@;
}

done_testing;
