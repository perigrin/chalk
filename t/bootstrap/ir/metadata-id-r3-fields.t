# ABOUTME: Teeth for ClassInfo/MethodInfo id() — the content-hash key must
# ABOUTME: include the R3-added fields so two structs differing only in them
# ABOUTME: do not collide (and get silently deduped) in a hash-cons key.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::MethodInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::NodeFactory;

my $f = Chalk::IR::NodeFactory->new;
sub node { my ($v) = @_; my $n = $f->make('Constant', value => $v, const_type => 'integer'); $n }

subtest 'MethodInfo id() distinguishes return_repr' => sub {
    my $a = Chalk::IR::MethodInfo->new(name => 'm', return_repr => 'Int');
    my $b = Chalk::IR::MethodInfo->new(name => 'm', return_repr => 'Str');
    isnt($a->id, $b->id,
        'two MethodInfos differing only in return_repr have distinct ids');
};

subtest 'MethodInfo id() distinguishes body_node' => sub {
    my $a = Chalk::IR::MethodInfo->new(name => 'm', body_node => node(1));
    my $b = Chalk::IR::MethodInfo->new(name => 'm', body_node => node(2));
    isnt($a->id, $b->id,
        'two MethodInfos differing only in body_node have distinct ids');
};

subtest 'ClassInfo id() distinguishes adjusts' => sub {
    my $a = Chalk::IR::ClassInfo->new(name => 'C', adjusts => [[node(1)]]);
    my $b = Chalk::IR::ClassInfo->new(name => 'C', adjusts => [[node(2)]]);
    isnt($a->id, $b->id,
        'two ClassInfos differing only in adjusts have distinct ids');
};

subtest 'ClassInfo id() distinguishes parent_ci' => sub {
    my $p1 = Chalk::IR::ClassInfo->new(name => 'P1');
    my $p2 = Chalk::IR::ClassInfo->new(name => 'P2');
    my $a  = Chalk::IR::ClassInfo->new(name => 'C', parent_ci => $p1);
    my $b  = Chalk::IR::ClassInfo->new(name => 'C', parent_ci => $p2);
    isnt($a->id, $b->id,
        'two ClassInfos differing only in parent_ci have distinct ids');
};

subtest 'identical structs still share an id (dedup still works)' => sub {
    my $a = Chalk::IR::MethodInfo->new(name => 'm', return_repr => 'Int');
    my $b = Chalk::IR::MethodInfo->new(name => 'm', return_repr => 'Int');
    is($a->id, $b->id, 'identical MethodInfos still collapse to one id');

    my $ca = Chalk::IR::ClassInfo->new(name => 'C', adjusts => []);
    my $cb = Chalk::IR::ClassInfo->new(name => 'C', adjusts => []);
    is($ca->id, $cb->id, 'identical ClassInfos still collapse to one id');
};

done_testing;
