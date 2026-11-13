# ABOUTME: A sub's per-context copy whose returned call only its context types
# ABOUTME: (Scalar) still types the Phi that merges that call with another return.
use 5.42.0;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

my $SON = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
plan skip_all => "perl5-son not found at $SON (set PERL5_SON_LIB)" unless -f "$SON/B/SoN.pm";
plan skip_all => 'lli not found (set LLI)' unless -x ( $ENV{LLI} // '/usr/lib/llvm-15/bin/lli' );
require Chalk::CodeGen::Harness::TapDiff;

# resolve() returns $node or pad_vd($node); called in scalar context it gets a
# copy whose pad_vd() call is typed only by that context, after inference.
my $src = <<'PERL';
package N; sub new { bless { op => $_[1], in => $_[2] }, $_[0] } sub operation { $_[0]{op} } sub inputs { $_[0]{in} }
package main;
sub pad_vd { my ($node) = @_; return undef unless $node->can('operation') && $node->operation eq 'PadAccess'; my $in = $node->inputs->[0]; return ( defined $in && $in->can('operation') && $in->operation eq 'VarDecl' ) ? $in : undef; }
sub resolve { my ($node) = @_; return undef unless defined $node; return $node if $node->can('operation') && $node->operation eq 'VarDecl'; return pad_vd($node); }
my $vd = N->new('VarDecl', []); my $pa = N->new('PadAccess', [$vd]);
for my $x ($vd, $pa, N->new('Other', []), undef) { my $r = resolve($x); print defined $r ? $r->operation : 'undef', "\n" }
PERL
my ( $fh, $pl ) = tempfile( SUFFIX => '.pl', UNLINK => 1 );
print $fh $src; close $fh;
my $r = Chalk::CodeGen::Harness::TapDiff->compare($pl);
unlike $r->{why} // '', qr/untyped Value node/, 'the merge of the returned call is typed';

done_testing;
