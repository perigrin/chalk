# ABOUTME: Tests ClassRegistry for multi-class XS compilation.
# ABOUTME: Verifies class registration, UseDecl following, and compilation order.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# --- Test 1: ClassRegistry loads ---
use_ok('Chalk::Bootstrap::Perl::Target::ClassRegistry');

# --- Test 2: Basic registration and resolution ---
{
    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
    isa_ok($reg, 'Chalk::Bootstrap::Perl::Target::ClassRegistry');

    # Register with mock data
    $reg->register('Foo::Bar', { ir => 'ir1', sa => 'sa1', ctx => 'ctx1' });
    $reg->register('Foo::Baz', { ir => 'ir2', sa => 'sa2', ctx => 'ctx2' });

    # Resolve
    my $entry = $reg->resolve('Foo::Bar');
    ok(defined $entry, 'resolve finds registered class');
    is($entry->{ir}, 'ir1', 'resolve returns correct IR');
    is($entry->{sa}, 'sa1', 'resolve returns correct SA');

    # Resolve unknown
    my $missing = $reg->resolve('Foo::Unknown');
    ok(!defined $missing, 'resolve returns undef for unknown class');

    # All classes
    my @classes = sort $reg->all_classes();
    is_deeply(\@classes, ['Foo::Bar', 'Foo::Baz'], 'all_classes returns all registered');
}

# --- Test 3: compilation_order returns topological sort ---
{
    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();

    # Register with dependency info
    $reg->register('A', { ir => 'a', sa => 'sa', ctx => 'ctx', uses => ['B', 'C'] });
    $reg->register('B', { ir => 'b', sa => 'sa', ctx => 'ctx', uses => ['C'] });
    $reg->register('C', { ir => 'c', sa => 'sa', ctx => 'ctx', uses => [] });

    my @order = $reg->compilation_order();
    # C must come before B, B before A
    my %pos;
    for my ($i, $v) (indexed @order) {
        $pos{$v} = $i;
    }
    ok($pos{'C'} < $pos{'B'}, 'C compiled before B (B uses C)');
    ok($pos{'B'} < $pos{'A'}, 'B compiled before A (A uses B)');
}

# --- Test 4: compilation_order with unknown dependencies ---
{
    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();

    # A uses D which is not registered (external dependency)
    $reg->register('A', { ir => 'a', sa => 'sa', ctx => 'ctx', uses => ['D'] });

    my @order = $reg->compilation_order();
    is_deeply(\@order, ['A'], 'unknown dependencies are skipped in compilation order');
}

# --- Test 5: XS.pm accepts class_registry parameter ---
{
    use Chalk::Bootstrap::Perl::Target::XS;
    my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
    my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
        module_name => 'Test::Multi',
        class_registry => $reg,
    );
    ok(defined $xs, 'XS emitter accepts class_registry parameter');
}

done_testing();
