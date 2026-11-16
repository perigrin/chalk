# ABOUTME: Which subs a method call may run is known by its name (call_targets): @_ is aliased
# ABOUTME: only as they need, and a list a sub returns is of temporaries, its array aliased as it is.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}


my @same = (
    [ q{package S { sub new { bless { n => $_[1] }, $_[0] } sub name { $_[0]{n} } } package C { sub new { bless {}, shift } sub subs { (S->new("a"), S->new("b"), S->new("a")) } } sub root { my ($s) = @_; return \$_[0] } sub f { my ($cls) = @_; my $reg = { subs => [] }; for my $s ($cls->subs) { my $sname = $s->name; next if grep { ($_->{name} // '') eq $sname } @{ $reg->{subs} }; my $b = root($s); push @{ $reg->{subs} }, { name => $sname, same => ($$b == $s ? 1 : 0) } } join ",", map { "$_->{name}:$_->{same}" } @{ $reg->{subs} } } print f(C->new), "\n";},
      'a reference into @_ of a foreach alias over a method\'s list' ],
    [ q{package S { sub new { bless { n => $_[1] }, $_[0] } } package C { sub list { (S->new("a"), S->new("b")) } } sub root { \$_[0] } my @r; for my $s (C->list) { my $b = root($s); push @r, ($$b == $s ? 1 : 0) } print "@r\n";},
      'a class method\'s list' ],
    [ q{sub two { (1, 2) } sub g { $_[0] .= "x"; $_[1] } my @r; for my $v (two()) { push @r, g($v, $v) } print "@r\n";},
      'a sub\'s list written through @_' ],
    [ q{package P { sub new { bless {}, shift } sub m { $_[1] } } sub root { \$_[0] } my $o = P->new; my $v = $o->m(5); my $r = root($v); $$r = 9; print "$v\n";},
      'a store through a reference into @_ reaches the variable' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

my @refused = (
    [ q{my $x = 1; sub lv :lvalue { $x } sub g { $_[0] = 7 } g(lv()); print "$x\n";},
      'an :lvalue sub\'s list (its variables) written through @_' ],
    [ q{sub root { \$_[0] } sub k { "lit" } my $r = root("x"); my $q = root(k()); print "$$r $$q\n"; $$q = 3; print "$$q\n";},
      'a literal referenced through @_' ],
);

for my $case (@refused) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    isnt $r->{verdict}, 'DIFFERS', "$name: never a wrong answer" or diag explain $r;
    like $r->{why} // '', qr/T2: out of its slices/, "$name: refused by name" if $r->{verdict} eq 'REFUSED';
}

done_testing;
