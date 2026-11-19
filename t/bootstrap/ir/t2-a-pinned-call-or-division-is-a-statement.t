# ABOUTME: What B::SoN pins on the control chain runs where it stands: a method named by a value,
# ABOUTME: a division or modulus that may die on zero, a printf. Perl's answer, exit status too.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
use Chalk::CodeGen::Harness::LLI;
my $LLI = Chalk::CodeGen::Harness::LLI->lli;
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";

require Chalk::CodeGen::Pipeline;
require Chalk::CodeGen::Harness::Producer;

sub wire ($src) {
    my ($fh, $pl) = tempfile(SUFFIX => '.pl', UNLINK => 1);
    print $fh $src;
    close $fh;
    return ( scalar qx($^X -I$SON -MO=-q,SoN,json $pl 2>/dev/null), $pl );
}

# The whole program through B::SoN, chalk's pipeline and lli: [stdout and
# stderr, exit status], beside perl's own.
sub both ($src) {
    my ($json, $pl) = wire($src);
    my $select = sub ($graphs, $mop) {
        my $g = $graphs->{'main::__PROGRAM__'} or return ();
        my $ret = $g->returns->[0] or return ();
        return ([ 'main::__PROGRAM__', $ret ]);
    };
    my ($units, undef, undef, $err) = Chalk::CodeGen::Pipeline->new->run_detail($json, $select, program_mode => 1);
    die "load: $err\n" if $err;
    die "lower: $units->[0]{err}\n" unless $units->[0]{ok};
    my ($lf, $ll) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $lf, ':utf8';
    print $lf $units->[0]{ll};
    close $lf;
    my ($ef, $errf) = tempfile(SUFFIX => '.err', UNLINK => 1);
    close $ef;
    my $slurp = sub { local ( @ARGV, $/ ) = $errf; scalar <> };
    my $got  = qx(timeout 20 $LLI $ll 2>$errf </dev/null);
    my ($grc, $gerr) = ( $? >> 8, $slurp->() );
    my $want = qx($^X $pl 2>$errf </dev/null);
    my ($wrc, $werr) = ( $? >> 8, $slurp->() );
    return ( [ $got, $grc, $gerr ], [ $want, $wrc, $werr ] );
}

# same($src, $name, stderr => 1): chalk's program prints what perl's does to
# STDOUT and ends with perl's status; with `stderr`, STDERR's text too.
sub same ($src, $name, %opt) {
    my ($got, $want) = eval { both($src) };
    is( $@, '', "$name: lowered" ) or return;
    is( $got->[0], $want->[0], "$name: perl's output" );
    is( $got->[1], $want->[1], "$name: perl's exit status" );
    is( $got->[2], $want->[2], "$name: perl's STDERR" ) if $opt{stderr};
}

# A printf: its format's string to the handle, where it stands; its value 1.
same( q{printf("%s-%d\n", "made", 3); print "x\n";},                       'a printf statement' );
same( q{print "a\n"; printf "%05.1f|%-4s|%x\n", 3.14159, "ab", 255; print "b\n";}, 'a printf between prints' );
same( q{sub mk { return bless {}, $_[0] } my $o = mk("K"); my $ok = printf("%s\n", "made"); print "$ok\n";}, 'a printf taken for its value (ef30)' );
same( q{printf STDERR "%d!\n", 3; printf STDOUT "%s\n", "out";},          'a printf to STDERR and to STDOUT by name', stderr => 1 );
same( q{for my $i (1 .. 3) { printf "%d,", $i * 2 } printf "\n";},        'a printf in a loop' );
{
    eval { both(q{my $fh = \*STDOUT; printf {$fh} "%s\n", "a";}) };
    like( $@, qr/GAP: .*a printf whose first operand is no format written out/, 'a printf to a handle in a variable: refused by name' );
    eval { both(q{my $f = @ARGV ? "%d\n" : "%s\n"; printf $f, 3;}) };
    like( $@, qr/GAP: .*a printf whose first operand is no format written out/, 'a printf of a format made at run time: refused by name' );
}

# A METHOD NAMED BY A VALUE, called for what it does: it runs where it stands.
SKIP: {
    my $dyn1 = qq{package C; sub new { bless {n=>0}, shift } sub inc { \$_[0]{n}++; return }\npackage main; my \$o = C->new; my \$m = "inc"; \$o->\$m(); print \$o->{n}, "\\n";};
    skip 'this B::SoN leaves a dynamic method call off the control chain', 15 unless Chalk::CodeGen::Harness::Producer->pins_dynamic_method_calls;
    same( $dyn1, 'a dynamic method call as a statement (dyn1)' );
    same( qq{package C; sub new { bless {n=>0}, shift } sub inc { \$_[0]{n}++; return 5 }\npackage main; my \$o = C->new; my \$m = "inc"; my \$r = \$o->\$m(); print "\$r \$o->{n}\\n";},
        'a dynamic method call read after a field it wrote (dyn2)' );
    same( qq{package C; sub new { bless {n=>0}, shift } sub add { \$_[0]{n} += \$_[1]; return \$_[0]{n} }\npackage main; my \$o = C->new; for my \$m (("add") x 3) { \$o->\$m(2); print \$o->{n}, ";" } print "\\n";},
        'a dynamic method call in a loop body' );
    same( qq{package C; sub new { bless {}, shift } sub hi { print "hi \$_[1]\\n"; return }\npackage main; my \$o = C->new; my \$m = \$ARGV[0] // "hi"; print "a\\n"; \$o->\$m("there"); print "b\\n";},
        'a dynamic method call between prints' );
    same( qq{package C; sub new { bless {}, shift } sub hi { return "hi" }\npackage main; my \$o = C->new; my \$m = "nope"; print "a\\n"; \$o->\$m(); print "b\\n";},
        'a dynamic method call of no such method dies where it stands' );
}

# A DIVISION OR MODULUS THAT MAY DIE ON ZERO dies where it stands, not at
# its value's first use.
SKIP: {
    my $fl1 = q{my $d = @ARGV; my $q = 1 / $d; print "before\n"; print "$q\n";};
    skip 'this B::SoN leaves a division that may fault off the control chain', 26 unless Chalk::CodeGen::Harness::Producer->pins_divisions;
    same( $fl1, 'a division by zero before a print (fl1)', stderr => 1 );
    same( q{my $d = @ARGV; my $q = 7 % $d; print "before\n"; print "$q\n";},                                  'a modulus by zero before a print (fl6)', stderr => 1 );
    same( q{my $d = @ARGV; print "a\n"; my $q = eval { 1 / $d } // "inf"; print "$q\n";},                      'a division by zero in an eval (fl3)' );
    same( q{my $r = eval { 1 / 0 }; print defined $r ? "d" : "u:", ($@ =~ /division/ ? "div" : "?"), "\n";},  'a division by a literal zero in an eval (im20)' );
    same( q{my $d = @ARGV + 4; my $q = 6 / $d; my $r = 7 % $d; print "before\n"; print "$q $r\n";},            'a divisor that is not zero divides' );
    same( q{my $d = @ARGV; print "a\n"; print 1 / $d, "\n"; print "b\n";},                                    'a division by zero printed after a print' );
    # (in a loop body itself B::SoN refuses the division, by its own name)
    same( q{sub q { my $q = 12 / $_[0]; print "in\n"; return $q } my @d = (2, 1, 0, 3); for my $d (@d) { print "d$d\n"; print q($d), "\n" } print "end\n";},
        'a division in a sub a loop calls dies on the pass its divisor is zero' );
    same( q{my $d = @ARGV; my $q; if ($d == 0) { print "a\n"; $q = 5 % $d; print "b\n" } else { $q = 1 } print "$q\n";}, 'a modulus by zero in an arm' );
}

done_testing;
