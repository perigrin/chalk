# ABOUTME: Call nodes carry the statically-known class as a class_name attribute
# ABOUTME: (hashed when present) — class structure never rides as a node input.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;

# Per docs/plans/2026-06-11-llvm-reads-mop-directly.md: class structure is
# compile-time context resolved by name against a registry built from the
# sealed MOP. The Call node names its class; inputs carry only runtime
# values (:param values for new, invocant + args for method dispatch).

subtest 'class_name rides as a reader attribute' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $v = $f->make('Constant', value => '5', const_type => 'integer');

    my $new = $f->make('Call', dispatch_kind => 'method', name => 'new',
        class_name => 'Pt', param_names => ['x'], inputs => [$v]);
    is($new->class_name, 'Pt', 'constructor call names its class');

    my $get = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$new]);
    is($get->class_name, 'Pt', 'method-dispatch call names its class');

    my $builtin = $f->make('Call', dispatch_kind => 'builtin', name => 'push',
        inputs => [$v]);
    is($builtin->class_name, undef, 'class_name defaults to undef');
};

subtest 'class_name is serialized in content_hash when present' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $v = $f->make('Constant', value => '5', const_type => 'integer');

    my $a = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Pt', inputs => [$v]);
    my $b = $f->make('Call', dispatch_kind => 'method', name => 'val',
        class_name => 'Other', inputs => [$v]);
    isnt($a->content_hash, $b->content_hash,
        'different classes produce different content hashes');
    like($a->content_hash, qr/class_name=Pt/,
        'the hash names the class explicitly');

    my $no_class = $f->make('Call', dispatch_kind => 'builtin', name => 'push',
        inputs => [$v]);
    unlike($no_class->content_hash, qr/class_name/,
        'absent class_name leaves the hash shape unchanged (back-compat)');
};

done_testing;
