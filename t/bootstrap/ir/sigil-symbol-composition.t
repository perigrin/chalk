# ABOUTME: Pins that PadAccess/EntryDef expose one sigil-qualified name accessor.
# ABOUTME: The wire splits sigil from symbol; consumers must never re-compose it by hand.
use 5.42.0;
use utf8;
use Test2::V0;
use lib 'lib';

use Chalk::IR::Node::PadAccess;
use Chalk::IR::Node::EntryDef;

# The wire carries `sigil` and `symbol` SEPARATELY, and `symbol` is BARE
# ('x', not '$x'). Every consumer wants the qualified spelling. If each one
# composes it itself, a missed site is a SILENT no-match rather than an error
# -- which is exactly how the same rename cost the producer two regressions.
# So the composition lives in ONE place: `name`.

subtest 'PadAccess composes sigil + symbol into name' => sub {
    my $n = Chalk::IR::Node::PadAccess->new(
        id => 1, targ => 4, sigil => '$', symbol => 'x', inputs => [],
    );
    is $n->sigil,  '$', 'sigil is readable on its own';
    is $n->symbol, 'x',  'symbol is BARE -- no sigil';
    is $n->name,   '$x', 'name is the qualified spelling';
};

subtest 'EntryDef composes sigil + symbol, and keeps package' => sub {
    my $n = Chalk::IR::Node::EntryDef->new(
        id => 2, package => 'main', sigil => '$', symbol => 'g', inputs => [],
    );
    is $n->package, 'main', 'package replaces stash_name';
    is $n->symbol,  'g',    'symbol is BARE';
    is $n->name,    '$g',   'name is the qualified spelling';
};

# The identity argument recorded in EntryDef.pm: `_` alone names THREE things
# ($_, @_, and the `-f _` filetest handle). A name-only identity hash-consed
# the first two into ONE node. The sigil must stay identity-bearing.
subtest 'sigil stays identity-bearing under the split' => sub {
    my %common = (package => 'main', symbol => '_', inputs => []);
    my $scalar = Chalk::IR::Node::EntryDef->new(id => 3, sigil => '$', %common);
    my $array  = Chalk::IR::Node::EntryDef->new(id => 4, sigil => '@', %common);
    isnt $scalar->content_hash, $array->content_hash,
        '$_ and @_ do NOT hash-cons together';
};

subtest 'PadAccess identity distinguishes sigils too' => sub {
    my %common = (targ => 0, symbol => 'a', inputs => []);
    my $s = Chalk::IR::Node::PadAccess->new(id => 5, sigil => '$', %common);
    my $a = Chalk::IR::Node::PadAccess->new(id => 6, sigil => '@', %common);
    isnt $s->content_hash, $a->content_hash, '$a and @a are different variables';
};

done_testing;
