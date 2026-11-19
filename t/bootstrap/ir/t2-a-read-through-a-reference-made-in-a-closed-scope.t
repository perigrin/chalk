# ABOUTME: A read through a reference made in a loop body or an arm, before a call after
# ABOUTME: that scope closed, was read there: settled, not refused as waiting across the call.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;
use File::Temp qw(tempfile);

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
use Chalk::CodeGen::Harness::LLI;
Chalk::CodeGen::Harness::LLI->lli;
require Chalk::CodeGen::Harness::TapDiff;

sub tap ($src) {
    my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
    print $fh $src; close $fh;
    return Chalk::CodeGen::Harness::TapDiff->compare($pl);
}

my @same = (
    # THE MAP'S BODY read @$_ for its call: a call after the map is no reason to refuse it
    [ q{my %t; sub f { my ($c, $a, $b) = @_; if ($c) { if ($a && $b) { $t{$b} = $a; return } } } my @r = map { scalar(f(@$_)) // "u" } [1,"P",3],[1,"P",0],[1,"",4],[0,1,1]; my @l = f(1,"Q",0); print "@r|", scalar(@l), "|", join(",", map {"$_=$t{$_}"} sort keys %t), "\n";},
      'a deref map\'s body read, then a call' ],
    [ q{my %in = (a => [[1, 2], 3], b => [4]); my @dead; push @dead, qw(a b); my @seen; for my $d (@dead) { for my $i ($in{$d}->@*) { if (ref $i) { for my $e ($i->@*) { push @seen, "$d$e" } } else { push @seen, "$d$i" } } } print "@seen\n";},
      'derefs in nested loop bodies, then a push' ],
    # A READ RESTING ON ONE SETTLED in the body (the count of @flat) is settled too:
    # not made again at the store after the loops
    [ q{package N { sub new { my ($c, @in) = @_; bless { in => [@in] }, $c } sub inputs { $_[0]{in} } } package C { sub new { bless { memo => {} }, shift } sub f { my ($self, $node) = @_; my $r = 0; $self->{memo}{"$node"} = 0; INPUT: for my $input ($node->inputs()->@*) { my @flat = (ref($input) eq 'ARRAY') ? $input->@* : ($input); for my $el (@flat) { next unless defined $el && ref $el; if ($self->f($el)) { $r = 1; last INPUT } } } return $self->{memo}{"$node"} = $r || 1 } } print C->new->f(N->new(1, [2, 3])), C->new->f(N->new(1, [2, N->new])), "\n";},
      'a choice of a deref in a loop body, its count read past a store after the loop' ],
    [ q{my %h = (a => [1, 2], b => [3]); sub g { $_[0] * 10 } my @r = map { scalar(g(@$_)) } @h{qw(a b)}; my @k = sort keys %h; g(1); print "@r @k\n";},
      'a deref in a map over a slice, then calls' ],
);

for my $case (@same) {
    my ($src, $name) = @$case;
    my $r = tap("$src\n");
    is $r->{verdict}, 'SAME', $name or diag $r->{why} // explain $r;
}

done_testing;
