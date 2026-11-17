# ABOUTME: Grammar gaps that kept lib/Chalk/*.pm out of perl-recognize-phase5.t:
# ABOUTME: punctuation variables, package-qualified aggregates and postfix slices.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
unless (defined $ir) {
    plan skip_all => 'Perl grammar failed to parse';
    exit;
}
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new()->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase5Gaps/g;
eval $generated;
if ($@) {
    plan skip_all => "Generated grammar code failed: $@";
    exit;
}
my $grammar    = Chalk::Grammar::Perl::Phase5Gaps::grammar();
my $recognizer = build_perl_recognizer($grammar, start => 'Program');
my $parser     = build_perl_ir_parser($grammar, start => 'Program');

# The Boolean recognizer is what perl-recognize-phase5.t runs; the full
# five-semiring parser must also come out with exactly one parse (it dies on
# an ambiguity the filters leave) and build IR.
my sub ir_of($src) {
    $parser->semiring->reset_cache();
    my $ctx = $parser->parse_value($src);
    return undef if !defined $ctx || $ctx->is_zero();
    return $ctx->extract();
}

my sub accepts($src, $label) {
    subtest $label => sub {
        ok($recognizer->parse($src), "recognized: $src");
        my $ir = eval { ir_of($src) };
        is($@, '', 'the full pipeline does not die');
        ok(defined $ir, "parsed to IR: $src");
    };
}

my sub rejects($src, $label) {
    ok(!$recognizer->parse($src), $label);
}

# Walk an IR tree (a Program's statements, inputs, arrayrefs) and return
# every node.
my sub all_nodes($root) {
    my (@out, %seen);
    my @todo = ($root);
    while (@todo) {
        my $n = shift @todo;
        next unless defined $n && ref $n;
        if (ref $n eq 'ARRAY') { push @todo, $n->@*; next }
        next if $seen{ refaddr($n) }++;
        if ($n isa Chalk::IR::Program) { push @todo, $n->other_stmts()->@*; next }
        next unless $n isa Chalk::IR::Node;
        push @out, $n;
        push @todo, $n->inputs()->@* if $n->can('inputs') && ref $n->inputs() eq 'ARRAY';
        push @todo, $n->items()->@*  if $n->can('items')  && ref $n->items() eq 'ARRAY';
        push @todo, $n->stmts()->@*  if $n->can('stmts')  && ref $n->stmts() eq 'ARRAY';
    }
    return @out;
}
use Scalar::Util qw(refaddr);

# ============================================================================
# §1 Punctuation variables. perl -c accepts each in an expression position;
# `$,`, `$;` and `$$` are left out: they collide with the signature
# placeholder (`($,)`), the statement terminator and `$$ref`.
# ============================================================================

accepts('my $e = $@;',                      '$@ (eval error)');
accepts('die $@ if $@;',                    '$@ as a postfix-if condition');
accepts('my $m = $@ =~ s/\n.*//sr;',        '$@ bound to a substitution');
accepts('my $e = $!;',                      '$! (errno)');
accepts('open(my $fh, "<", $f) or die "$f: $!";', '$! inside a string stays opaque');
accepts('die $!;',                          '$! as a call argument');
accepts('local $/;',                        '$/ (input record separator)');
accepts('local $\ = "\n";',                 '$\\ (output record separator)');
accepts('my $n = $.;',                      '$. (input line number)');
accepts('my $w = $&;',                      '$& (last match)');
accepts('my $o = $^O;',                     '$^O (control-character name)');
accepts('local $^W = 0;',                   '$^W assigned');
accepts('my $b = ${^WARNING_BITS};',        '${^NAME} (caret-brace name)');
accepts('my $z = $0;',                      '$0 (program name, a digit variable)');
rejects('my $e = $@@;',                     'rejects $@@');

# The rest of perlvar's punctuation variables (perl -c accepts each in an
# expression position): one token each, so each stays one reading.
for my $v ('$?', '$`', q{$'}, '$+', '$|', '$"', '$%', '$=', '$-', '$~', '$^',
           '$:', '$<', '$>', '$(', '$)', '$[', '$]', '$^N', '$#-', '$#+',
           '$#{^CAPTURE}') {
    accepts("my \$v = $v;", "$v (punctuation variable)");
}
for my $v ('@-', '@+', '@{^CAPTURE}') {
    accepts("my \@v = $v;", "$v (punctuation array)");
}
for my $v ('%+', '%-', '%!', '%^H', '%{^CAPTURE}', '%{^CAPTURE_ALL}') {
    accepts("my \%v = $v;", "$v (punctuation hash)");
}
accepts('die "x" unless $? == 0;',          '$? compared, as Impl.pm does');
accepts('my $s = $-[0] . $+[1];',           'elements of @- and @+');
accepts('my $n = $+{name} // $-{name};',    'elements of %+ and %-');
accepts('my $c = $? ? 1 : 0;',              '$? as a ternary condition');
accepts('my $x = $c ? $::y : $z;',          '$::y in a ternary arm stays one variable, not $: then :y');
accepts('local $| = 1;',                    '$| assigned');
accepts('my $w = $^W;',                     '$^W stays one variable, not $^ then W');
{
    my $ir = ir_of('my $v = $?;');
    my ($var) = grep { $_->operation() eq 'Constant' && ($_->value() // '') eq '$?' } all_nodes($ir);
    ok(defined $var, '$? builds the variable $?');
}

# ============================================================================
# §2 Package-qualified aggregates (and `$::x`, the main-package short form).
# ============================================================================

accepts('my @a = @Pkg::x;',                 '@Pkg::x');
accepts('my %h = %Pkg::x;',                 '%Pkg::x');
accepts('my $s = $Pkg::x;',                 '$Pkg::x (pre-existing)');
accepts('my @a = @Pkg::Sub::x;',            '@Pkg::Sub::x');
accepts('my @a = @::x;',                    '@::x');
accepts('my %h = %::x;',                    '%::x');
accepts('my $s = $::x;',                    '$::x');
accepts('our @ISA = @Foo::ISA;',            'our @ISA = @Foo::ISA');
accepts('my $n = scalar @Pkg::x;',          'scalar of a qualified array');
accepts('my $v = $Pkg::x{a};',              'element of a qualified hash');
rejects('my @a = @Pkg::;',                  'rejects @Pkg:: (a stash name: out of the subset, spec section 2)');
rejects('my @a = @::;',                     'rejects @:: (the main stash)');

# ============================================================================
# §3 Postfix slices. perl: `$r->@[...]` and `$r->@{...}` are slices,
# `$r->%[...]` and `$r->%{...}` key/value slices; the sigil and the bracket
# are one token (`$r->@ [0]` is a syntax error).
# ============================================================================

accepts('my @v = $r->@[0];',                '->@[ one index ] (pre-existing)');
accepts('my @v = $r->@[0, 1];',             '->@[ a list of indices ]');
accepts('my @v = $r->@[0 .. $#a];',         '->@[ a range ] (pre-existing)');
accepts('$g->{prog}[$L]->@[ 1, 2 ] = $c ? ( $B, $E ) : ( $E, $B );',
                                            '->@[ list ] as an assignment target');
accepts('my @v = $r->@{qw(a b)};',          '->@{ qw list }');
accepts('my @v = $r->@{"a", "b"};',         '->@{ list of keys }');
accepts('my @v = $r->@{a};',                '->@{ bareword key }');
accepts('delete $v->@{qw(inner completed leo)};', 'delete of a postfix hash slice');
# Key/value slices are recognized; the IR has no node for one yet, so the
# actions refuse it by name rather than build a plain slice (a miscompile).
for my $kv ('my %kv = $r->%[0, 1];', 'my %kv = $r->%{a};', 'my %kv = $r->%{qw(a b)};') {
    ok($recognizer->parse($kv), "recognized: $kv");
    my $ir = eval { ir_of($kv) };
    like($@, qr/GAP: .*key\/value slice/, "... the actions refuse it as a GAP: $kv");
}
accepts('my $last = $r->$#*;',              '->$#* (pre-existing)');
accepts('my @x = $r->@*;',                  '->@* (pre-existing)');
rejects('my @v = $r->@ [0];',               'rejects whitespace between @ and [');
rejects('my @v = $r->% {a};',               'rejects whitespace between % and {');
rejects('my @v = $r->@{};',                 'rejects an empty postfix slice');

# The slices build Slice IR over the dereferenced aggregate.
{
    my $ir = ir_of('my @v = $r->@[0, 1];');
    my ($slice) = grep { $_->operation() eq 'Slice' } all_nodes($ir);
    ok(defined $slice, '->@[0, 1] builds a Slice');
    is($slice && $slice->kind(), 'array', '... of kind array');
    my @in = $slice ? $slice->inputs()->@* : ();
    is(scalar(@in), 3, '... with two indices and the aggregate');
    ok(@in && $in[-1]->operation() eq 'PostfixDeref' && $in[-1]->sigil() eq '@',
        '... the aggregate last: the array $r refers to');
}
{
    my $ir = ir_of('my @v = $r->@{qw(a b)};');
    my ($slice) = grep { $_->operation() eq 'Slice' } all_nodes($ir);
    ok(defined $slice, '->@{qw(a b)} builds a Slice');
    is($slice && $slice->kind(), 'hash', '... of kind hash');
    my @in = $slice ? $slice->inputs()->@* : ();
    is(scalar(@in), 3, '... with two keys and the aggregate');
    ok(@in && $in[-1]->operation() eq 'PostfixDeref' && $in[-1]->sigil() eq '%',
        '... the aggregate last: the hash $r refers to');
}

# ============================================================================
# §4 `//` before a string holding a `/`. A regex literal read from the second
# `/` of `//` ends inside the string; the chart GC took that for a safe set
# and freed the string's origin (earley-chart-gc.t has the grammar-free case).
# ============================================================================

accepts('my $x = $c // out("a/b");',        '// then a call whose string holds a /');
accepts('my $x = $c // ("a/b");',           '// then a parenthesized string holding a /');
accepts('my $x = $c // $d->f("a/b");',      '// then a method call whose string holds a /');
accepts('my $x = $c // f(" / ");',          '// then a string holding a spaced /');
accepts("out('x') unless \$c // out('a/b');", "// in a modifier, single-quoted 'a/b'");
{
    my $ir = ir_of('my $x = $c // out("a/b");');
    my ($dor) = grep { $_->operation() eq 'DefinedOr' } all_nodes($ir);
    ok(defined $dor, '$c // out("a/b") builds a defined-or');
}

done_testing();
