# ABOUTME: Calls of subs with signatures through T2 alone, against perl: a method call's
# ABOUTME: arity checked as perl dies, a default the body computes, a list passed to a sub.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

for my $src (
    # A SIGNATURE CALLED AS A METHOD: its wrapper checks the count, and
    # where it is another perl dies -- naming the sub and the call's line.
    qq{use v5.36;\npackage Optimizer { sub collapse (\$, \$phi) { return "c\$phi" } }\nprint Optimizer->collapse(7), "\\n";\neval { Optimizer->collapse(); 1 }; print \$@;\neval { Optimizer->collapse(1, 2, 3); 1 }; print \$@;\n},
    qq{use v5.36;\npackage K { sub f (\$s, \$a, \$b = 2) { return \$a + \$b } }\nprint K->f(1), K->f(1, 5), "\\n";\neval { K->f(1, 2, 3, 4) }; print \$@;\neval { K->f() }; print \$@;\n},
    qq{use v5.36;\npackage K { sub f (\$s, \$a, \@r) { return "\$a:" . scalar(\@r) } }\nprint K->f(1), K->f(1, 2, 3), "\\n";\neval { K->f() }; print \$@;\n},
    # A METHOD OF THE CLASS FEATURE WITH A SLURPY PARAMETER: the rest of
    # its arguments, a copy; at least its others, or perl dies.
    q{use v5.42; use experimental "class"; class K { field $p = "<"; method f($x, @g) { "$p$x:@g" } method g(@a) { scalar(@a) } } my $k = K->new; print $k->f(1,2,3), $k->f(9), $k->g(), $k->g(4,5), "\n"; eval { $k->f() }; print $@;},
    q{use v5.42; use experimental "class"; class K { method isn($x) { $x =~ /a/ } method f(@g) { my @r = sort @g; my @n = grep { $self->isn($_) } @r; return "@n" } } print K->new->f(qw(ba x aa)), "\n";},
    # A DEFAULT THE BODY COMPUTES: called where no argument was passed.
    q{use v5.36; our $c = 0; sub g { $c++; 5 } sub f ($x = g()) { $x + 1 } print f(), f(1), " c=$c\n";},
    # A LIST PASSED to a sub taking `my (...) = @_`: its count is the list's.
    q{sub f { my ($c, $a, $b) = @_; return "$c$a" . ( $b // "u" ) } my $r = [1, "P"]; my @x = (2, "Q", 3); print f(@$r), f(@x), f(0, @$r), "\n";},
) {
    my $r = tap($src =~ /\n\z/ ? $src : "$src\n");
    is $r->{verdict}, 'SAME', $src or diag $r->{why} // explain $r;
}

done_testing;
