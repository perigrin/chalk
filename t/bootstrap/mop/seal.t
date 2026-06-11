# ABOUTME: MOP seal(): post-parse the MOP is enforceably immutable — declare_* dies
# ABOUTME: after seal on the registry and on every class; sealing is idempotent.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::MOP;

# The MOP metaobjects are mutable because they are parse-time accumulators
# (declare_* fires per member as the Earley actions complete). seal() marks
# the moment construction ends: the post-parse read surface — what the LLVM
# backend's class registry is built from — must not silently grow.

subtest 'declare works before seal, dies after' => sub {
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');
    $cls->declare_field('x', sigil => '$', attributes => [':param']);
    $cls->declare_method('val');
    $cls->declare_adjust();

    ok(!$mop->is_sealed, 'fresh MOP is not sealed');
    ok(!$cls->is_sealed, 'fresh class is not sealed');

    $mop->seal;

    ok($mop->is_sealed, 'MOP reports sealed');
    ok($cls->is_sealed, 'seal propagates to every registered class');

    my $err;
    eval { $mop->declare_class('Late'); 1 } or $err = $@;
    like($err, qr/sealed/, 'declare_class on a sealed MOP dies');

    for my $case (
        [ declare_field   => sub { $cls->declare_field('y', sigil => '$') } ],
        [ declare_method  => sub { $cls->declare_method('late') } ],
        [ declare_sub     => sub { $cls->declare_sub('late') } ],
        [ declare_import  => sub { $cls->declare_import('Late::Mod') } ],
        [ declare_adjust  => sub { $cls->declare_adjust() } ],
    ) {
        my ($name, $code) = @$case;
        my $e;
        eval { $code->(); 1 } or $e = $@;
        like($e, qr/sealed/, "$name on a sealed class dies");
    }
};

subtest 'seal propagates across multiple classes' => sub {
    my $mop = Chalk::MOP->new;
    my $a = $mop->declare_class('A');
    my $b = $mop->declare_class('B');
    $mop->seal;
    ok($a->is_sealed && $b->is_sealed, 'both classes sealed');
    my $err;
    eval { $b->declare_method('late'); 1 } or $err = $@;
    like($err, qr/sealed/, 'declaring on the second class dies too');
};

subtest 'seal is idempotent' => sub {
    my $mop = Chalk::MOP->new;
    $mop->declare_class('A');
    $mop->seal;
    my $ok = eval { $mop->seal; 1 };
    ok($ok, 'sealing twice does not die');
    ok($mop->is_sealed, 'still sealed');
};

subtest 'reads still work after seal' => sub {
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Pt');
    my $m = $cls->declare_method('val');
    $mop->seal;

    is($mop->for_class('Pt'), $cls, 'for_class reads fine');
    is(($cls->methods)[0], $m, 'methods reads fine');
    is($mop->find_method('val'), $m, 'find_method reads fine');
};

done_testing;
