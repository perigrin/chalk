# ABOUTME: G6 regex sub-compiler — RegexMatch lowers a literal pattern to a
# ABOUTME: runtime-free LLVM matcher (no libperl/perl-regex-engine), lli==perl.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

my $LLI = '/usr/lib/llvm-15/bin/lli';
unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI";
}

# Lower a Return node, run lli, return (stdout, ll-text). Dies on lli error.
sub lli_run {
    my ($ret) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret);
    require File::Temp;
    my ($fh, $f) = File::Temp::tempfile(SUFFIX => '.ll', UNLINK => 1);
    print $fh $ll;
    close $fh;
    my $out = `$LLI $f 2>&1`;
    my $exit = $? >> 8;
    die "lli failed (exit $exit): $out\n--- .ll ---\n$ll" if $exit;
    chomp $out;
    return ($out, $ll);
}

sub _mk { Chalk::IR::NodeFactory->new }

# Build RegexMatch($subject_str =~ /$pattern/) -> Bool (matched?).
# The pattern is a compile-time literal attr (NOT a graph input) — that is what
# makes the match runtime-free.
sub match_node {
    my ($f, $subject, $pattern) = @_;
    my $subj = $f->make('Constant', value => $subject, const_type => 'string');
    $subj->set_representation('Str');
    my $m = $f->make('RegexMatch', pattern => $pattern, flags => '', inputs => [$subj]);
    $m->set_representation('Bool');
    return $m;
}

# T0: literal substring match — "foobar" =~ /foo/ is true.
subtest 'T0 literal match: "foobar" =~ /foo/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', 'foo');
    my $ret = $f->make_cfg('Return', inputs => [$m]);

    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    is($out, 'Bool:1', 'matched literal substring => Bool:1');
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        'matcher .ll is libperl-free');
};

# T0: literal non-match — "foobar" =~ /xyz/ is false.
subtest 'T0 literal non-match: "foobar" =~ /xyz/ => Bool:' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', 'xyz');
    my $ret = $f->make_cfg('Return', inputs => [$m]);

    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    is($out, 'Bool:', 'non-matching literal => Bool: (false)');
};

# T0: match not at offset 0 — "xfoo" =~ /foo/ is true (slide loop finds it).
subtest 'T0 literal match mid-string: "xfoo" =~ /foo/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'xfoo', 'foo');
    my $ret = $f->make_cfg('Return', inputs => [$m]);

    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };

    is($out, 'Bool:1', 'matched substring at non-zero offset => Bool:1');
};

# ---------------------------------------------------------------------------
# T1: anchors — ^ (start), $ (end), ^...$ (full string).
# ^ collapses the slide loop to offset 0 only; $ requires the match to end at
# the subject length.
# ---------------------------------------------------------------------------

subtest 'T1 ^anchor: "foobar" =~ /^foo/ => Bool:1 (matches at start)' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', '^foo');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/^foo/ matches "foobar" at offset 0');
};

subtest 'T1 ^anchor non-match: "xfoo" =~ /^foo/ => Bool: (not at start)' => sub {
    my $f = _mk();
    my $m = match_node($f, 'xfoo', '^foo');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/^foo/ does NOT match "xfoo" (foo is not at offset 0)');
};

subtest 'T1 $anchor: "foobar" =~ /bar$/ => Bool:1 (matches at end)' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', 'bar$');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/bar$/ matches "foobar" at the end');
};

subtest 'T1 $anchor non-match: "foobar" =~ /foo$/ => Bool: (not at end)' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', 'foo$');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/foo$/ does NOT match "foobar" (foo is not at the end)');
};

subtest 'T1 full-string ^...$: "foo" =~ /^foo$/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foo', '^foo$');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/^foo$/ matches exactly "foo"');
};

subtest 'T1 full-string non-match: "foobar" =~ /^foo$/ => Bool:' => sub {
    my $f = _mk();
    my $m = match_node($f, 'foobar', '^foo$');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/^foo$/ does NOT match "foobar"');
};

# ---------------------------------------------------------------------------
# T2: character classes — [...], negated [^...], ranges, \d \w \s shorthands,
# and `.` (any char). Each class atom is a predicate over one subject byte.
# ---------------------------------------------------------------------------

subtest 'T2 class range: "a9z" =~ /[0-9]/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'a9z', '[0-9]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/[0-9]/ finds the digit in "a9z"');
};

subtest 'T2 class range non-match: "abc" =~ /[0-9]/ => Bool:' => sub {
    my $f = _mk();
    my $m = match_node($f, 'abc', '[0-9]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/[0-9]/ does NOT match "abc"');
};

subtest 'T2 multi-range class: "_x" =~ /^[A-Za-z_]/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, '_x', '^[A-Za-z_]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/^[A-Za-z_]/ matches "_x" (underscore in class)');
};

subtest 'T2 multi-range class non-match: "9x" =~ /^[A-Za-z_]/ => Bool:' => sub {
    my $f = _mk();
    my $m = match_node($f, '9x', '^[A-Za-z_]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/^[A-Za-z_]/ does NOT match "9x"');
};

subtest 'T2 negated class: "abc" =~ /[^0-9]/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'abc', '[^0-9]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/[^0-9]/ matches a non-digit in "abc"');
};

subtest 'T2 negated class non-match: "123" =~ /[^0-9]/ => Bool:' => sub {
    my $f = _mk();
    my $m = match_node($f, '123', '[^0-9]');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:', '/[^0-9]/ does NOT match an all-digit subject');
};

subtest 'T2 \\d shorthand: "x7" =~ /\\d/ => Bool:1' => sub {
    my $f = _mk();
    my $m = match_node($f, 'x7', '\\d');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out, $ll);
    eval { ($out, $ll) = lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/\\d/ finds the digit in "x7"');
};

subtest 'T2 \\w shorthand: "--a" =~ /\\w/ => Bool:1; "---" => Bool:' => sub {
    my $f = _mk();
    my $m1 = match_node($f, '--a', '\\w');
    my $r1 = $f->make_cfg('Return', inputs => [$m1]);
    my ($o1) = eval { lli_run($r1) };
    ok(!$@, "lowering + lli succeeded (match)") or do { diag("error: $@"); return };
    is($o1, 'Bool:1', '/\\w/ matches the word char in "--a"');

    my $f2 = _mk();
    my $m2 = match_node($f2, '---', '\\w');
    my $r2 = $f2->make_cfg('Return', inputs => [$m2]);
    my ($o2) = eval { lli_run($r2) };
    ok(!$@, "lowering + lli succeeded (non-match)") or do { diag("error: $@"); return };
    is($o2, 'Bool:', '/\\w/ does NOT match "---"');
};

subtest 'T2 dot: "ab" =~ /a.b/ vs "axb" — . matches any char' => sub {
    my $f = _mk();
    my $m = match_node($f, 'axb', 'a.b');
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, "lowering + lli succeeded") or do { diag("error: $@"); return };
    is($out, 'Bool:1', '/a.b/ matches "axb" (dot = any char)');
};

subtest 'T2 escaped literal: "a.b" =~ /a\\.b/ => Bool:1; "axb" => Bool:' => sub {
    my $f = _mk();
    my $m1 = match_node($f, 'a.b', 'a\\.b');
    my $r1 = $f->make_cfg('Return', inputs => [$m1]);
    my ($o1) = eval { lli_run($r1) };
    ok(!$@, "lowering + lli succeeded (escaped dot match)") or do { diag("error: $@"); return };
    is($o1, 'Bool:1', '/a\\.b/ matches literal "a.b"');

    my $f2 = _mk();
    my $m2 = match_node($f2, 'axb', 'a\\.b');
    my $r2 = $f2->make_cfg('Return', inputs => [$m2]);
    my ($o2) = eval { lli_run($r2) };
    ok(!$@, "lowering + lli succeeded (escaped dot non-match)") or do { diag("error: $@"); return };
    is($o2, 'Bool:', '/a\\.b/ does NOT match "axb" (escaped dot is literal)');
};

# ---------------------------------------------------------------------------
# T3: greedy quantifiers — * + ? {n,m}. The inner recognizer becomes
# position-threaded: a quantified atom greedily consumes then BACKS OFF if the
# continuation fails (real backtracking, not naive maximal-munch).
# ---------------------------------------------------------------------------

# Helper: run one match and compare to expectation.
sub try_match {
    my ($subject, $pattern, $want, $label) = @_;
    my $f = _mk();
    my $m = match_node($f, $subject, $pattern);
    my $ret = $f->make_cfg('Return', inputs => [$m]);
    my ($out) = eval { lli_run($ret) };
    if ($@) { fail("$label: lowering/lli failed: $@"); return }
    is($out, $want, $label);
}

subtest 'T3 star: /ab*c/ — zero, many, and broken-tail cases' => sub {
    try_match('ac',     'ab*c', 'Bool:1', '"ac"    =~ /ab*c/ (zero b)');
    try_match('abbbc',  'ab*c', 'Bool:1', '"abbbc" =~ /ab*c/ (many b)');
    try_match('abx',    'ab*c', 'Bool:',  '"abx"   !~ /ab*c/ (broken tail)');
};

subtest 'T3 plus: /ab+c/ — requires at least one' => sub {
    try_match('ac',    'ab+c', 'Bool:',  '"ac"   !~ /ab+c/ (plus needs >=1)');
    try_match('abc',   'ab+c', 'Bool:1', '"abc"  =~ /ab+c/');
    try_match('abbc',  'ab+c', 'Bool:1', '"abbc" =~ /ab+c/');
};

subtest 'T3 optional: /ab?c/ — zero or one' => sub {
    try_match('ac',    'ab?c', 'Bool:1', '"ac"   =~ /ab?c/ (zero)');
    try_match('abc',   'ab?c', 'Bool:1', '"abc"  =~ /ab?c/ (one)');
    try_match('abbc',  'ab?c', 'Bool:',  '"abbc" !~ /ab?c/ (two is too many)');
};

subtest 'T3 backtracking keystone: /a*ab/ — greedy must back off' => sub {
    # Naive maximal-munch eats all the a's and then fails on 'ab'.
    # Correct greedy-with-backoff matches: a* takes "aa", then "ab" matches.
    try_match('aaab', 'a*ab', 'Bool:1', '"aaab" =~ /a*ab/ (backoff required)');
    try_match('b',    'a*ab', 'Bool:',  '"b"    !~ /a*ab/');
};

subtest 'T3 counted: /^a{2,3}$/ — bounded repetition' => sub {
    try_match('aa',    '^a{2,3}$', 'Bool:1', '"aa"   =~ /^a{2,3}$/');
    try_match('aaa',   '^a{2,3}$', 'Bool:1', '"aaa"  =~ /^a{2,3}$/');
    try_match('a',     '^a{2,3}$', 'Bool:',  '"a"    !~ /^a{2,3}$/ (too few)');
    try_match('aaaa',  '^a{2,3}$', 'Bool:',  '"aaaa" !~ /^a{2,3}$/ (too many)');
};

subtest 'T3 the dominant lib/ shape: /^[A-Za-z_][A-Za-z0-9_]*$/' => sub {
    my $pat = '^[A-Za-z_][A-Za-z0-9_]*$';
    try_match('foo_1', $pat, 'Bool:1', '"foo_1" is a valid identifier');
    try_match('_',     $pat, 'Bool:1', '"_" is a valid identifier');
    try_match('9bad',  $pat, 'Bool:',  '"9bad" is NOT (leading digit)');
    try_match('',      $pat, 'Bool:',  '"" is NOT (empty)');
    try_match('a-b',   $pat, 'Bool:',  '"a-b" is NOT (dash)');
};

subtest 'T3 class quantifier: /\d+/ finds a digit run' => sub {
    try_match('x42',  '\\d+', 'Bool:1', '"x42" =~ /\\d+/');
    try_match('xyz',  '\\d+', 'Bool:',  '"xyz" !~ /\\d+/');
};

done_testing;
