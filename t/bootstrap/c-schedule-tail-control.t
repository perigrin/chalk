# ABOUTME: Phase 7d smoke test for a control-flow node at the tail (implicit-return) position.
# ABOUTME: Verifies _emit_c_schedule_item handles synthetic Return wrapping If/Loop/TryCatch via _expand_node.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use TestPipeline qw(parse_perl_source);
use Chalk::Bootstrap::Perl::Target::C;

# Construct a minimal class whose method has a control-flow value
# at the tail position (the implicit return).
my $src = <<'PERL';
class Test::VarDeclControl {
    method tail_if($self, $x) {
        if ($x) { 1 } else { 0 }
    }
}
PERL

my $mop = Chalk::MOP->new;
Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
my ($ir, $sa, $ctx) = parse_perl_source($src);
ok(defined $ctx, 'parse succeeds');

my $mop_class;
for my $cls ($mop->classes) {
    next if $cls->name eq 'main';
    $mop_class = $cls;
}
ok(defined $mop_class, 'class found in MOP');

SKIP: {
    skip 'no class', 1 unless defined $mop_class;
    my $target = Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Test::VarDeclControl',
    );
    my $result = eval { $target->_generate_c_files($ir, $sa, $ctx) };
    ok(defined $result, '_generate_c_files succeeds for tail-if method') or do {
        diag "Error: $@";
    };
}

done_testing();
