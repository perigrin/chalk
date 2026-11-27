# ABOUTME: Grammar gaps that kept lib/Chalk/*.pm out of chalk-recognizes-its-own-source.t:
# ABOUTME: punctuation variables, package-qualified aggregates and postfix slices.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
unless (defined $ir) {
    die 'Perl grammar failed to parse', "\n";
    exit;
}
my $generated = Chalk::Bootstrap::BNF::Target::Perl->new()->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::Phase5Gaps/g;
eval $generated;
if ($@) {
    die "Generated grammar code failed: $@", "\n";
    exit;
}
my $grammar    = Chalk::Grammar::Perl::Phase5Gaps::grammar();
my $recognizer = build_perl_recognizer($grammar, start => 'Program');
my $parser     = build_perl_ir_parser($grammar, start => 'Program');

# The Boolean recognizer is what chalk-recognizes-its-own-source.t runs; the full
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

# ============================================================================
# §4b A statement modifier after a comma expression: `A, B if C;` is
# `(A, B) if C` (perl -MO=Deparse). IR/Serialize/JSON.pm has one whose
# operands hold `//` and strings. The grammar already took these (the
# modifier attaches to SimpleStatement, after an ExpressionList); pinned.
# ============================================================================

accepts('$a = 1, $b = 2 if $c;',            'A, B if C');
accepts('f(1), g(2) unless $c;',            'A, B unless C');
accepts('$a, $b if $c;',                    'a bare comma list under a modifier');
accepts(q{( $x = $by{ ( $x->{inputs} // [] )->[0] // '' } // {} ), $i = $x->{op} // ''
    if $i eq 'Subscript';},                 'JSON.pm\'s form: // operands, a parenthesized assignment, the modifier on the next line');

# ============================================================================
# §5 qx// and backticks: a command whose output is the value. perl
# interpolates the command as a double-quoted string; it becomes a
# BacktickExpr over that string, interpolated as a double-quoted string
# is (an array, an element too). What the double-quoted string action does
# not model (a caret variable) is refused as a GAP, never handed to the
# shell as text.
# ============================================================================

accepts('my $o = qx(ls -la);',              'qx(...)');
accepts('my $o = qx{ls -la};',              'qx{...}');
accepts('my $o = qx[ls -la];',              'qx[...]');
accepts('my $o = qx(echo $name 2>/dev/null);', 'qx(...) interpolating a scalar, with a redirect');
accepts('my $o = `ls -la`;',                'backticks (pre-existing in the grammar)');
accepts('my @lines = qx(ls);',              'qx in list context');
accepts('my $ok = qx(true) =~ /x/;',        'qx bound to a match');
rejects('my $o = qx(ls;',                   'rejects an unterminated qx(');
# The Boolean recognizer reads `qx ls` as a call of a sub qx (keywords are
# not reserved in the grammar); the full parser's keyword check refuses it.
ok(!defined eval { ir_of('my $o = qx ls;') }, 'the full parser refuses qx with no delimiter');
{
    my $ir = ir_of('my $o = qx(ls -la);');
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    ok(defined $bt, 'qx(ls -la) builds a BacktickExpr');
    my $cmd = $bt && $bt->inputs()->[0];
    ok($cmd && $cmd->operation() eq 'Constant' && $cmd->value() eq 'ls -la',
        '... over the command text');
}
{
    my $ir = ir_of('my $o = `ls -la`;');
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    ok(defined $bt, '`ls -la` builds a BacktickExpr, not a string');
    ok(!grep({ $_->operation() eq 'Constant' && ($_->value() // '') =~ /`/ } all_nodes($ir)),
        '... and no string Constant holds the backticks');
}
{
    my $ir = ir_of('my $o = qx(echo $name);');
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    my $cmd = $bt && $bt->inputs()->[0];
    ok($cmd && $cmd->operation() eq 'Interpolate', 'qx(echo $name) interpolates the command');
}
for my $src ('my $o = qx(echo @a);', 'my $o = qx(echo $h{k});') {
    my $ir = ir_of($src);
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    my $cmd = $bt && $bt->inputs()->[0];
    ok($cmd && $cmd->operation() eq 'Interpolate', "$src interpolates the command");
}
{
    # A caret variable interpolates as any variable does (Impl.pm runs
    # `qx($^X -I$SON ...)`).
    my $src = 'my $o = qx($^X -e 1);';
    ok($recognizer->parse($src), "recognized: $src");
    my $ir = ir_of($src);
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    my $cmd = $bt && $bt->inputs()->[0];
    ok($cmd && $cmd->operation() eq 'Interpolate'
        && (grep { $_->operation() eq 'Constant' && ($_->value() // '') eq '$^X' } $cmd->inputs()->[0]->@*),
        "$src interpolates the variable \$^X");
}
{
    # \cX is a control character: \cW is chr(23), \c? chr(127).
    my $ir = ir_of(q{my $s = "a\cW\c?";});
    ok((grep { $_->operation() eq 'Constant' && ($_->value() // '') eq "a\x17\x7f" } all_nodes($ir)),
        q{"a\cW\c?" is a, chr(23), chr(127)});
}

# ============================================================================
# §6 Circumfix dereference of any expression: @{ EXPR } and %{ EXPR }, the
# aggregate EXPR refers to (perl: `EXPR->@*`, `EXPR->%*`). The sigil and its
# brace are one token here (perl also takes `@ {`; lib/ never writes it).
# ============================================================================

accepts('my ( $lo, $hi ) = @{ shift @in };', '@{ shift @in }, as IR/Analysis.pm has it');
accepts('my @a = @{$r};',                   '@{$r}');
accepts('my @a = @{ $self->{items} };',     '@{ $self->{items} }');
accepts('my @a = @{ $x->[0] // [] };',      '@{ EXPR // [] }');
accepts('my %h = %{$r};',                   '%{$r}');
accepts('my %h = %{ $self->{map} };',       '%{ $self->{map} }');
accepts('my @k = keys %{ $self->{map} };',  'keys %{ ... }');
accepts('my $n = scalar @{ $r };',          'scalar @{ ... }');
accepts('for my $x (@{ $self->list() }) { }', '@{ ... } as a foreach list');
accepts('push @{ $h{$k} }, $v;',            'push onto @{ ... }');
accepts('my $n = @{$r} + 1;',               '@{ ... } as an operand');
accepts('return %{$r};',                    'return %{ ... }');
accepts('f(%{$r}, @{$s});',                 'both as call arguments');
accepts('my @a = @{ $r }; my $m = $a % 2;', 'a % operator elsewhere stays an operator');
rejects('my @a = @{ };',                    'rejects an empty @{ }');
rejects('my @a = @{ $r ;',                  'rejects an unclosed @{');
for my $case (['my @a = @{ shift @in };', '@', 'Call'],
              ['my %h = %{ $self->{map} };', '%', 'Subscript']) {
    my ($src, $sigil, $inner) = $case->@*;
    my $ir = ir_of($src);
    my ($d) = grep { $_->operation() eq 'PostfixDeref' } all_nodes($ir);
    ok(defined $d, "$src builds a PostfixDeref");
    is($d && $d->sigil(), $sigil, "... of sigil $sigil");
    is($d && $d->inputs()->[0]->operation(), $inner, "... over the expression ($inner)");
}
# An element or slice of a circumfix deref (`@{$r}[0]`, `%{$h}{a}`) is not
# modelled: refused by name rather than read as an element of the aggregate.
for my $src ('my @v = @{$r}[0];', 'my %v = %{$h}{a};') {
    ok($recognizer->parse($src), "recognized: $src");
    eval { ir_of($src) };
    like($@, qr/GAP: .*circumfix/, "... the actions refuse it as a GAP: $src");
}

# ============================================================================
# §7 Loop labels: `LABEL: for/foreach/while/until ...`, and next/last/redo
# LABEL. The label is the Loop's; a jump names it with a `label` Constant.
# ============================================================================

accepts('TIE: for my $t (@a) { next TIE unless $t; }', 'a labelled foreach and next LABEL, as IR/Analysis.pm has it');
accepts('OUTER: while ($x) { INNER: for my $y (@a) { next OUTER if $y; last INNER; } }',
                                            'nested labelled loops jumping out of the inner one');
accepts('L: until ($d) { redo L if $x; }',  'a labelled until and redo LABEL');
accepts('L: for (my $i = 0; $i < 3; $i++) { last L; }', 'a labelled C-style for');
accepts('L: foreach (@a) { last L }',       'a labelled foreach with no iterator variable');
accepts('L : for (@a) { }',                 'space before the label colon');
accepts('l: for (@a) { next l }',           'a lower-case label');
accepts('for (@a) { next; last; }',         'next and last without a label (pre-existing)');
accepts('my $v = $c ? A : B;',              'a ternary over barewords stays a ternary');
accepts('Foo::Bar->new;',                   'a package name at statement start is no label');
rejects('L: ;',                             'rejects a label on an empty statement');
{
    my $ir = ir_of('TIE: for my $t (@a) { next TIE unless $t; }');
    my ($loop) = grep { $_->operation() eq 'Loop' } all_nodes($ir);
    ok(defined $loop, 'a labelled foreach builds a Loop');
    is($loop && $loop->label(), 'TIE', '... carrying its label');
}
{
    my $ir = ir_of('for (@a) { }');
    my ($loop) = grep { $_->operation() eq 'Loop' } all_nodes($ir);
    is($loop && $loop->label(), undef, 'an unlabelled Loop has no label');
}
# A label on a bare block (`L: { ... last L }`): the IR has no loop-once
# block to carry it, so the actions refuse it by name.
{
    my $src = 'L: { last L; }';
    ok($recognizer->parse($src), "recognized: $src");
    eval { ir_of($src) };
    like($@, qr/GAP: .*label.*block/, "... the actions refuse a labelled bare block as a GAP");
}

# ============================================================================
# §8 A filehandle as print's indirect object: `print $fh LIST`, `print {EXPR}
# LIST` (and printf, say). perl 5.42 decides by the text after `print $name`
# and its whitespace: a term start makes $name the handle, an operator start
# makes it the first value (`print $x $y` vs `print $x - $y`). Each verdict
# below is perl's own (B::Concise shows an rv2gv for the handle).
# ============================================================================

# [source, 1 if perl reads the scalar as the handle]
my @print_cases = (
    ['print $fh $json;',                1],   # Impl.pm
    ['print $fh "a", "b";',             1],
    ['printf $fh "%s\n", $x;',          1],
    ['say $fh $x;',                     1],
    ['print {$fh} "a";',                1],
    ['print { $self->{out} } "a", "b";', 1],
    ['print($fh "a");',                 1],
    ['print ($fh "a");',                1],
    ['print $fh -1;',                   1],
    ['print $x - 1;',                   0],
    ['print $x -$y;',                   1],
    ['print $x / 2;',                   0],
    ['print $x . "a";',                 0],
    ['print $x, $y;',                   0],
    ['print $x;',                       0],
    ['print $x x 3;',                   0],
    ['print $x eq 1;',                  0],
    ['print $x if $y;',                 0],
    ['print $x ? 1 : 2;',               0],
    ['print $x (1);',                   1],
    ['print $x lc $y;',                 1],
    ['print $x %h;',                    1],
    ['print $x % 2;',                   0],
    ["print \$fh\n  \"a\";",            1],
    ['print $x::y "a";',                1],
    ['print $x [1];',                   0],
    ['print $x{a};',                    0],
    ['my $ok = print $x -1;',           1],
    ['print $x !$y;',                   1],
    ['print $x != 1;',                  0],
    ['print $x \$y;',                   1],
    ['print $_ "a";',                   1],
    ['print $x->{a};',                  0],
    ['print $x =~ /a/;',                0],
    ['print $x // 1;',                  0],
);
for my $case (@print_cases) {
    my ($src, $fh) = $case->@*;
    accepts($src, $fh ? "handle: $src" : "no handle: $src");
    my $ir = eval { ir_of($src) };
    my ($call) = grep { $_->operation() eq 'Call' && ($_->name() // '') =~ /\A(?:print|printf|say)\z/ }
        all_nodes($ir);
    is($call && $call->indirect_handle() ? 1 : 0, $fh,
        $fh ? "... the scalar is print's handle" : "... print has no handle");
}
{
    my $ir = ir_of('print $fh $json;');
    my ($call) = grep { $_->operation() eq 'Call' && $_->name() eq 'print' } all_nodes($ir);
    my @args = $call ? $call->inputs()->[1]->@* : ();
    is(scalar(@args), 2, 'print $fh $json: the handle, then one value');
    ok(@args && $args[0]->operation() eq 'Constant' && $args[0]->value() eq '$fh',
        '... the handle first: $fh');
}
{
    my $ir = ir_of('print { $self->{out} } "a", "b";');
    my ($call) = grep { $_->operation() eq 'Call' && $_->name() eq 'print' } all_nodes($ir);
    my @args = $call ? $call->inputs()->[1]->@* : ();
    is(scalar(@args), 3, 'print {EXPR} LIST: the handle, then two values');
    ok(@args && $args[0]->operation() eq 'Subscript', '... the handle the block\'s expression');
    ok(!grep({ $_->operation() eq 'AnonSub' } all_nodes($ir)), '... and no AnonSub: the block is no sub');
}
accepts('print $x -1 if $y;',               'handle: print $x -1 under a postfix if');
# `print $x .5` is perl's handle reading too, but the grammar has no
# leading-dot number: it is refused, not read as `print($x . 5)`.
rejects('print $x .5;',                     'rejects print $x .5 (no .5 literal), rather than reading a concatenation');
# Another list operator does not take a handle: `die $x -1` is perl's
# "Missing comma" error, and the grammar's reading is the subtraction.
accepts('my @a = (join $sep, @b);',         'join with a scalar first argument stays a call');
accepts('push @a, $x -1;',                  'push with a later $x -1 is a subtraction');

# ============================================================================
# §9 Brace-delimited quote-likes nest their braces, as perl's do:
# Bootstrap/Perl/Target/Perl.pm has `s{...}{... sprintf('\\x{%x}', ...)}ge`.
# ============================================================================

accepts(q{$str =~ s{([\x00-\x1f])}{$E{$1} // sprintf('\\x{%x}', ord $1)}ge;},
                                            's{}{}e whose replacement nests braces, as Target/Perl.pm has it');
accepts(q{my $ok = $x =~ m{a{2}b};},        'm{} with a {n} quantifier');
accepts(q{my $ok = $x =~ s{a{2}}{b}r;},     's{}{} with a {n} quantifier in the pattern');
accepts(q{my $s = q{a{b}c};},               'q{} holding balanced braces');
accepts(q{my $s = qq{a{b}c};},              'qq{} holding balanced braces');
accepts(q{my $o = qx{echo {a}};},           'qx{} holding balanced braces');
rejects(q(my $s = q{a{b c};),               'rejects q{} with an unbalanced inner brace');
{
    my $ir = ir_of(q{my $o = qx{echo {a}};});
    my ($bt) = grep { $_->operation() eq 'BacktickExpr' } all_nodes($ir);
    my $cmd = $bt && $bt->inputs()->[0];
    is($cmd && $cmd->value(), 'echo {a}', 'qx{echo {a}} runs `echo {a}`');
}
# q() and qq() nest their parens as q{} its braces do (lib/Chalk/IR/Node/*
# spell `sub identity_kind { q(hash_consed) }`).
accepts(q{sub k { q(hash_consed) }},        'q() as a sub body');
accepts(q{my $s = q(a(b)c);},               'q() holding balanced parens');
accepts(q{my $s = qq (a(b)c);},             'qq () holding balanced parens');
for my $case ([q{my $s = q{a{b}c};}, 'a{b}c'], [q{my $s = qq{a{b}c};}, 'a{b}c'],
              [q{my $s = q[a\]b];}, 'a]b'], [q{my $s = qq[a\tb];}, "a\tb"],
              [q{my $s = q(a(b)\)c);}, 'a(b))c'], [q{my $s = qq(x\ty);}, "x\ty"]) {
    my ($src, $want) = $case->@*;
    my $ir = ir_of($src);
    my @strings = grep { $_->operation() eq 'Constant' && ($_->const_type() // '') eq 'string' }
        all_nodes($ir);
    ok((grep { $_->value() eq $want } @strings), "$src is the string without its delimiters")
        or diag(join ', ', map { $_->value() } @strings);
}

# ============================================================================
# §10 A postfix dereference in a double-quoted string: perl 5.42
# (postderef_qq) interpolates `$r->@*`, `$r->@[0]`, `$r->$*` and `$r->$#*`,
# and not `$r->%*`. The string action models none of the first four: it
# refuses them rather than keep them as text.
# ============================================================================

for my $src (q{my $s = "$r->@*";}, q{my $s = "$r->@[0]";}, q{my $s = "$r->$*";},
             q{my $s = "$r->{a}->$#*";}) {
    eval { ir_of($src) };
    like($@, qr/GAP: .*postfix dereference/, "refused, not kept as text: $src");
}
{
    my $ir = ir_of(q{my $s = "$r->%*";});
    my @lits = grep { $_->operation() eq 'Constant' && ($_->value() // '') eq '->%*' } all_nodes($ir);
    ok(scalar @lits, q{"$r->%*" keeps ->%* as text, as perl does});
}

# ============================================================================
# §11 A word perl quotes: before `=>` (perlop: "forces a word to its left to
# be interpreted as a string") and alone in a hash subscript's braces
# (perldata: "a simple identifier within such curlies is forced to be a
# string"). A keyword is no exception -- Regex/Parse.pm's `s => [...]`,
# Target/Perl.pm's `not => 30` and `$PREC_TERM{not}`, JSON.pm's
# `$f->{local}` -- and the word is the string, with one reading.
# perl -MO=Deparse: ('s', 1, 'undef', 2, 'not', 3, 'sub', 4, 'm', 5),
# $h{'s'}, $h{'undef'}, $h->{'not'}; `sub f { undef }` stays undef.
# ============================================================================

local $ENV{CHALK_COUNT_FILTER_TIES} = 1;
my sub strings_of($src) {
    $parser->semiring->flush_tie_log();
    my $ir = ir_of($src);
    my $ties = scalar $parser->semiring->tie_log()->@*;
    return ($ir, $ties, map { $_->value() }
        grep { $_->operation() eq 'Constant' && ($_->const_type() // '') eq 'string' } all_nodes($ir));
}
for my $case (
    [ 'my %h = (s => 1, m => 2, undef => 3, not => 4, sub => 5, time => 6, foo => 7);',
      [qw(s m undef not sub time foo)] ],
    [ 'my %h = (a => 1, -b => 2, q => 3, local => 4, __PACKAGE__ => 5);',
      [qw(a b q local __PACKAGE__)] ],
    [ 'my $v = $h{s} . $h{undef} . $r->{not} . $h{time} . $r->{local} . $h{ m } . $h{key};',
      [qw(s undef not time local m key)] ],
) {
    my ($src, $want) = $case->@*;
    my ($ir, $ties, @strings) = eval { strings_of($src) };
    is($@, '', "parses: $src");
    ok(defined $ir, "to IR: $src");
    is($ties, 0, "one reading: $src");
    my %have = map { $_ => 1 } @strings;
    is_deeply([grep { !$have{$_} } $want->@*], [], "each word is its string: $src")
        or diag('strings: ' . join(', ', @strings));
}
{
    # The word stays what it is where perl does not quote it.
    my ($ir, $ties, @strings) = strings_of('sub f { undef } my $x = { s => 1 }; my %m = ($o->name => 1, $o->s => 2);');
    is($ties, 0, 'a keyword in a block, a method name before =>: one reading');
    ok(!(grep { $_ eq 'undef' } @strings), 'sub f { undef } is undef, not a string')
        or diag('strings: ' . join(', ', @strings));
    my @calls = grep { $_->operation() eq 'Call' && $_->dispatch_kind() eq 'method' } all_nodes($ir);
    is(scalar @calls, 2, '$o->name => 1 and $o->s => 2 call their methods');
}

# ============================================================================
# §12 A named unary operator takes one operand, never a list (perlfunc: each
# of defined, ref, scalar, exists, delete, keys, values, each, shift, pop,
# length, chr, ord takes one EXPR). Actions.pm's Attribute returns
# `{ name => defined $n ? $n->value() : undef, value => defined $v ? ... }`;
# `defined` there may not take `$n ? ... : undef, value => defined $v` as its
# list. perl -MO=Deparse: {'name', defined $n ? $n->value : undef, ...}.
# ============================================================================
{
    my ($ir, $ties) = strings_of('my $h = { n => defined $n ? $n->v() : undef, w => defined $v ? $v->v() : undef };');
    ok(defined $ir, 'two defined-ternaries in a hash: parse');
    is($ties, 0, 'two defined-ternaries in a hash: one reading');
    my @defined = grep { $_->operation() eq 'Call' && ($_->name() // '') eq 'defined' } all_nodes($ir);
    is_deeply([map { scalar $_->inputs()->[1]->@* } @defined], [1, 1], 'each defined has one operand');
}

# ============================================================================
# §13 A bare call inside a postfix's own delimiters: perlop forbids `->`
# straight after a bare list-operator call (`foo @a->m` is no method call on
# foo's value), but a bare call as the ARGUMENT of a method call, or as a
# subscript's index, is delimited by the parens or brackets
# (Actions.pm: `$target->set_control_in(defined $bare ? ... : (...))`).
# perl -MO=Deparse: $t->s(defined $b), $t->s(defined $b ? 1 : 2).
# ============================================================================
for my $src ('$t->s(defined $b);', '$t->s(f $b);', '$t->s(defined $b ? 1 : (2));',
             'my $x = $h{ f $b };', 'my $x = $c->(defined $b);') {
    accepts($src, "a bare call inside the postfix's delimiters: $src");
}

# ============================================================================
# §14 An element whose index is an expression, in a double-quoted string:
# perl reads the bracketed text as code (toke.c's intuit_more: outside a
# pattern a `[` or `{` after a variable always starts a subscript), so
# "$x[$i - 1]" is the element at $i - 1 (LLVM/Printer.pm: `"$x[$_ - 1]()"`).
# The index is parsed by the expression grammar, the Subscript built as
# outside a string.
# ============================================================================
for my $case ([ 'my $s = "a $x[$i - 1] b";', 'Subtract' ], [ 'my $s = "$h{$k . q(b)}";', 'Concat' ],
              [ 'my $s = "$r->[$i * 2]{a}";', 'Multiply' ]) {
    my ($src, $op) = $case->@*;
    my $ir = eval { ir_of($src) };
    is($@, '', "parses: $src");
    my @subs = grep { $_->operation() eq 'Subscript' } all_nodes($ir);
    ok((grep { ($_->inputs()->[1] // 0) isa Chalk::IR::Node && $_->inputs()->[1]->operation() eq $op } @subs),
        "$src: the index is the $op the brackets hold");
}

# ============================================================================
# §15 A block of code in a double-quoted string: "${\ EXPR}" interpolates the
# scalar the block's value refers to, "@{[ LIST ]}" the array (perl reads
# the block as code, as for an index above). Each is the PostfixDeref of the
# block's expression (Target/C.pm: "${\  $self->_get_current_slug()}_$name").
# ============================================================================
for my $case ([ 'my $s = "a${\ $o->m()}b";', '$' ], [ 'my $s = "@{[ $n + 1 ]}";', '@' ]) {
    my ($src, $sigil) = $case->@*;
    my $ir = eval { ir_of($src) };
    is($@, '', "parses: $src");
    ok((grep { $_->operation() eq 'PostfixDeref' && $_->sigil() eq $sigil } all_nodes($ir)),
        "$src: the block's value dereferenced by $sigil");
}
{
    # `${name}` and `@{name}` stay the variable they name.
    my $ir = ir_of('my $s = "${ x }-@{y}";');
    my @v = map { $_->value() } grep { $_->operation() eq 'Constant' && ($_->const_type() // '') eq 'variable' } all_nodes($ir);
    is_deeply([sort grep { $_ ne '$s' } @v], ['$x', '@y'], '"${ x }-@{y}" interpolates $x and @y');
}

# ============================================================================
# §16 undef in a list declaration: `my (undef, $sg) = $b->field_of($n);`
# (LLVM/Builder/Containers.pm, Values.pm) skips the first value. perl
# -MO=Deparse: my(undef, $sg) = $b->field_of($n). The placeholder is the
# keyword undef in the ListAssign's names, and declares nothing.
# ============================================================================
{
    my $ir = eval { ir_of('my (undef, $sg) = f();') };
    is($@, '', 'my (undef, $sg) = f(): parses');
    my ($la) = grep { $_->operation() eq 'ListAssign' && defined $_->init() } all_nodes($ir);
    is_deeply([map { [$_->const_type(), $_->value()] } ($la ? $la->names()->@* : ())],
        [['undef', 'undef'], ['variable', '$sg']], 'its names: the undef placeholder, then $sg')
        or diag(join ', ', map { $_->value() } ($la ? $la->names()->@* : ()));
}

# ============================================================================
# §17 A C-style for: its three expressions are delimited by `(`, `;` and `)`,
# so a term in one (`$k++`) does not bind what the next one may hold
# (Regex/Pattern.pm: `for ($k++; $k < @$chars && ...; $k++)`).
# ============================================================================
accepts('for ($k++; $k < 3; $k++) { 1 }',  'for with a postfix increment as its init');
accepts('for ($k++; $k < @$c && $c->[$k] ne $q; $k++) { $k++ }', 'as Regex/Pattern.pm has it');

# ============================================================================
# §18 A statement after a list declaration: `my ($nm, @in) = (...)` may not
# lend its list to the statement after it, whose Expression and
# ExpressionList readings are then told apart as anywhere else
# (LLVM/Node/Values.pm, Target/EmitHelpers.pm).
# ============================================================================
for my $src ('sub f { my ($nm, @in) = ($o->name, 1); my %a = $o->attr->%*; return 1 }',
             'sub g { my ($l, $v) = ($1, $2); my $e = $o->esc($l); return $e }') {
    my ($ir, $ties) = strings_of($src);
    ok(defined $ir, "parses: $src");
    is($ties, 0, "one reading: $src");
}

for my $src ('sub h { my ($a, $b); ($a, $b) = $v->inputs; return $a }') {
    my ($ir, $ties) = strings_of($src);
    ok(defined $ir, "parses: $src");
    is($ties, 0, "a parenthesized list's list tag stays inside it: $src");
}

# ============================================================================
# §19 `//` is one token after a term: never `/` then a pattern starting with
# `/` (perlop; toke.c reads the longest operator). `( $n // '' ) eq '%' &&
# ( $c // '' )` once read `/ '' ) eq ... ( $c /` as a regex
# (LLVM/Builder/Variables.pm).
# ============================================================================
{
    my ($ir, $ties) = strings_of(q{sub f { return 0 if $op eq 'P' && ( $n->s // '' ) eq '%' && $c->o eq 'H' && ( $c->t // '' ) eq 'HR'; }});
    ok(defined $ir, 'two defined-ors in parens: parse');
    is($ties, 0, 'two defined-ors in parens: one reading');
}

# ============================================================================
# §20 `undef EXPR` as a statement: of a scalar, the scalar becomes undef
# (perlfunc; B::SoN rebinds it to undef). Of an aggregate it empties the
# container, a different operation, refused by name.
# ============================================================================
accepts('my $i = 1; undef $i;', 'undef $i');
accepts('my $i = 1; undef($i);', 'undef($i)');
{
    eval { ir_of('my @a = (1); undef @a;') };
    like($@, qr/GAP: undef of an aggregate/, 'undef @a is refused by name');
}

# ============================================================================
# §21 `++` and `--` are one token: `return ++$c` is a pre-increment, never
# + +$c (IR/Graph.pm). perl reads the longest operator.
# ============================================================================
for my $src ('sub f { return ++$c; }', 'sub g { return --$c; }') {
    my ($ir, $ties) = strings_of($src);
    is($ties, 0, "one reading: $src");
}
for my $src ('my $x = ++$c;', 'my $y = --$c;') {
    my ($ir) = strings_of($src);
    ok((grep { $_->operation() eq 'CompoundAssign' } all_nodes($ir)), "$src steps \$c");
}

done_testing();
