# ABOUTME: tie of a lexical scalar to a class the program declares: TIESCALAR on a
# ABOUTME: run-time class name, a read is FETCH, tied() its object; else refused.
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


# The program at $pl through B::SoN, chalk's pipeline and lli: its output
# (not stderr: an uncaught die's message is not lowered), then its exit code.
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
    my $out = qx($LLI $ll 2>/dev/null);
    return $out . "exit " . ($? >> 8);
}

sub file_of ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return $pl;
}


my $pkg = qq{package Counter;\nsub TIESCALAR { return bless {}, "Counter" }\nsub FETCH { return 42 }\npackage main;\n};
# pvm 415 416, and a class with no TIESCALAR: perl dies.
for my $case (
    [ $pkg . qq{tie my \$x, \$ENV{X} // "Counter", "a", "b";\nprint \$x, "\\n";\n}, undef ],
    [ $pkg . qq{tie my \$x, \$ENV{X} // "Counter";\nmy \$plain = 1;\nprint tied(\$x) ? "t" : "u", tied(\$plain) ? "t" : "u", "\\n";\n}, undef ],
    [ $pkg . qq{print "a\\n";\ntie my \$x, \$ENV{X} // "Counter";\nprint \$x, "\\n";\n}, 'Nope' ],
) {
    my ($src, $x) = @$case;
    my $pl = file_of($src);
    local $ENV{X} = $x;
    delete $ENV{X} unless defined $x;
    my $want = qx($^X $pl 2>/dev/null) . "exit " . ($? >> 8);
    my $got = eval { through_llvm_file($pl) } // "REFUSED $@";
    is($got, $want, "perl's answer, X=" . ( $x // 'unset' ) . ": " . ( $src =~ s/\n/ /gr ));
}

# A read before the tie, two reads (FETCH runs at each), a store: refused.
for my $src (
    $pkg . qq{my \$y = 1;\nprint "\$y\\n";\ntie \$y, "Counter";\nprint "\$y\\n";\n},
    $pkg . qq{tie my \$x, "Counter";\nprint \$x, \$x, "\\n";\n},
    $pkg . qq{tie my \$x, "Counter";\n\$x = 5;\nprint \$x, "\\n";\n},
) {
    my $got = eval { through_llvm_file(file_of($src)) } // "REFUSED $@";
    like($got, qr/\AREFUSED (?:lower|load): /, "refused: " . ( $src =~ s/\n/ /gr ));
}

done_testing;
