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

done_testing;
