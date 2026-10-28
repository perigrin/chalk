# ABOUTME: a method on a run-time class, and a call of what ->can found, do what
# ABOUTME: perl does: the sub's value, or perl's death (its exit; stdout as perl's).
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

# ->can of a sub the class has, called (pvm 059); and where the run-time
# class lacks it, perl's death -- an object of no such class, or one without.
my $can  = qq{package Foo;\nsub hi { return "called" }\npackage main;\nmy \$o = bless {}, \$ENV{X} // "Foo";\nprint \$o->can("hi")->(\$o), "\\n";\n};
my $meth = qq{package Foo;\nsub hi { return "hi" }\npackage main;\nmy \$o = bless {}, \$ENV{X} // "Foo";\nprint \$o->hi, "\\n";\n};
# In a block eval, perl catches that death: lowered as perl does, or refused.
my $in_eval = qq{package Foo;\nsub hi { return "hi" }\npackage main;\nmy \$o = bless {}, \$ENV{X} // "Foo";\nmy \$r = eval { \$o->hi };\nprint defined \$r ? \$r : "caught", "\\n";\n};
for my $case ([ $can, undef ], [ $can, 'Bar' ], [ $meth, 'Bar' ], [ $in_eval, 'Bar' ]) {
    my ($src, $x) = @$case;
    my $pl = file_of($src);
    local $ENV{X} = $x;
    delete $ENV{X} unless defined $x;
    my $want = qx($^X $pl 2>/dev/null) . "exit " . ($? >> 8);
    my $got = eval { through_llvm_file($pl) } // "REFUSED $@";
    next if $got =~ /\AREFUSED lower: GAP: / && $src eq $in_eval && pass("refused by name in an eval");
    is($got, $want, "perl's answer, X=" . ( $x // 'unset' ) . ": " . ( $src =~ s/\n/ /gr ));
}

done_testing;
