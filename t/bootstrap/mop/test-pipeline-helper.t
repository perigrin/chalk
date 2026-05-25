# ABOUTME: Test for TestPipeline::parse_perl_source convenience helper.
# ABOUTME: Verifies it returns (ir, sa, ctx) for a minimal Perl source string.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);

my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);

my $src = "class A { method f { 1 } }\n";
my ($ir, $sa, $ctx) = parse_perl_source($src);

ok(defined $ir,  'parse_perl_source returns defined ir');
ok(defined $sa,  'parse_perl_source returns defined sa');
ok(defined $ctx, 'parse_perl_source returns defined ctx');
isa_ok($ctx, 'Chalk::Bootstrap::Context', 'ctx is a Chalk::Bootstrap::Context');

# Post-propagation-fix (Tasks 1.2-1.4), ctx->mop is the installed MOP.
is(refaddr($ctx->mop), refaddr($mop), 'ctx->mop is the installed MOP');

done_testing();
