# ABOUTME: a method named by a value (`$o->$m`): a run-time dispatch of the method
# ABOUTME: its value names; a name read at run time, or one no package declares, as perl.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

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


my $pkg = qq{package Foo;\nsub hi { return "hi" }\nsub add { return \$_[1] + \$_[2] }\npackage main;\n};
# pvm 055, and with arguments.
for my $src (
    $pkg . qq{my \$o = bless {}, "Foo";\nmy \$m = "hi";\nprint \$o->\$m, "\\n";\n},
    $pkg . qq{my \$o = bless {}, \$ENV{X} // "Foo";\nmy \$m = "add";\nprint \$o->\$m(2, 3), "\\n";\n},
) {
    my $pl = file_of($src);
    my $want = qx($^X $pl 2>/dev/null) . "exit " . ($? >> 8);
    my $got = eval { through_llvm_file($pl) } // "REFUSED $@";
    is($got, $want, "perl's answer: " . ( $src =~ s/\n/ /gr ));
}

# A name read at run time, or one no package declares (perl dies: exit 255,
# nothing printed): perl's answer -- once refused, now looked up at run time.
for my $src (
    $pkg . qq{my \$o = bless {}, "Foo";\nmy \$m = \$ENV{M} // "hi";\nprint \$o->\$m, "\\n";\n},
    $pkg . qq{my \$o = bless {}, "Foo";\nmy \$m = "nope";\nprint \$o->\$m, "\\n";\n},
) {
    my $pl = file_of($src);
    my $want = qx($^X $pl 2>/dev/null) . "exit " . ($? >> 8);
    my $got = eval { through_llvm_file($pl) } // "REFUSED $@";
    is($got, $want, "perl's answer: " . ( $src =~ s/\n/ /gr ));
}

done_testing;
