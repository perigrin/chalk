# ABOUTME: A read through a reference (`keys %$h`, `@$r`, `$r->[0][1]`) may die, so B::SoN
# ABOUTME: pins it where it stands, a memory version: T2 makes it there, before the store or call after.
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

for my $case (
    [ q{my %v = (a => {n => "x"}, b => {n => "y"}); sub vars { \%v } sub emit { my $h = $_[0]; $h->{n} = "z"; "e" } sub f { my @l; for my $k (sort keys vars()->%*) { my $info = vars()->{$k}; my $s = $info->{n}; my $e = emit($info); push @l, "$s=$e" } "@l" } print f(), "\n";},
      'the keys of a hash a call returns, read before a call that stores into it' ],
    [ q{sub f { my ($g) = @_; my @l; for my $c (sort keys %$g) { my $f = $g->{$c}{f} // []; my @s = sort { $a->{i} <=> $b->{i} } @$f; push @l, "$c:" . join(",", map { $_->{i} } @s) } "@l" } print f({ A => { f => [{ i => 2 }, { i => 1 }] }, B => {} }), "\n";},
      'a hash through a parameter, read before a sort comparator' ],
    [ q{sub f { my $r = [[1, 2]]; my ($lv, $val) = ($r->[0][0], $r->[0][1]); $r->[0][0] = 9; return "$lv $val $r->[0][0]" } print f(), "\n";},
      'an element through an element, read before a store into it' ],
    [ q{package N { sub new { bless { i => $_[1] }, $_[0] } sub inputs { $_[0]{i} } } sub f { my ($p) = @_; my $in = $p->inputs; return "none" unless defined $in && @$in; my $n = N->new([]); return scalar(@$in) . ($n->inputs ? "y" : "n") } print f(N->new([1, 2])), f(N->new(undef)), "\n";},
      'an array a method returns, counted under && before a method call' ],
) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

# COUNTED THROUGH AN ELEMENT where it stands (`scalar @{ $h->{l} }`): an
# array there, its count; none, perl's -- it dies under strict refs (B::SoN
# names the site), its count is undef without -- never a count of a stand-in.
{
    my $r = tap(qq{sub f { my (\$s, \$t) = \@_; my \$g = scalar \@{ \$s->{s} }; push \$s->{s}->\@*, \$t; "x\$g" } my \$o = { s => [] }; print f(\$o, "a"), f(\$o, "b"), "\\n";\n});
    is $r->{verdict}, 'SAME', 'a count through an element, before a push into it' or diag $r->{why} // explain $r;
    $r = tap(qq{sub f { my (\$s) = \@_; my \$g = scalar \@{ \$s->{s} }; \$s->{t} = 1; "x\$g" } print f({}), "\\n";\n});
    is $r->{verdict}, 'SAME', 'none there, without strict refs: undef, as perl' or diag $r->{why} // explain $r;
    $r = tap(qq{use strict; sub f { my (\$s) = \@_; my \$g = scalar \@{ \$s->{s} }; \$s->{t} = 1; "x\$g" } print f({}), "\\n";\n});
    is $r->{verdict}, 'SAME', "none there, under strict refs: perl's die" or diag $r->{why} // explain $r;
}

done_testing;
