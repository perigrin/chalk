# ABOUTME: G7 $N magic-var graph edges — RegexCapture(match, n) reads capture N
# ABOUTME: as a NUL-terminated copy at the offsets the G6 _regex_captures contract records.
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

sub lli_run {
    my ($ret) = @_;
    my $ll = Chalk::Target::LLVM->lower($ret, program_mode => 1);
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

# Observe a value the way a program does: PRINT it, then return undef. A
# program's observable contract is stdout plus exit status; it has no side
# channel that hands a value back to a harness. The Print is appended AFTER
# the graph's last existing effect so any ordering under test is preserved.
sub print_and_return {
    my ($f, $value, $last_effect) = @_;

    # Print takes a Str, so a non-Str value is bridged with an explicit
    # Coerce -- the same node a source program's producer inserts.
    my $arg  = $value;
    my $repr = $value->stamp;
    if (!defined $repr || $repr ne 'Str') {
        $arg = $f->make('Coerce', inputs => [$value],
            from_repr => $repr, to_repr => 'Str');
        $arg->set_stamp('Str');
    }

    my $print = $f->make('Print', inputs => [$arg]);
    $print->set_control_in($last_effect // $f->make_cfg('Start'));

    my $undef = $f->make('Constant', value => undef, const_type => 'undef');
    $undef->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$undef]);
    $ret->set_control_in($print);
    return $ret;
}

# Build: $subject =~ /$pattern/ then RegexCapture(match, $n).
sub capture_graph {
    my ($f, $subject, $pattern, $n) = @_;
    my $subj = $f->make('Constant', value => $subject, const_type => 'string');
    $subj->set_stamp('Str');
    my $m = $f->make('RegexMatch', pattern => $pattern, flags => '', inputs => [$subj]);
    $m->set_stamp('Boolean');
    my $cap = $f->make('RegexCapture', n => $n, inputs => [$m]);
    $cap->set_stamp('Str');
    return ($m, $cap);
}

subtest '$1: "ab-cd" =~ /(\\w+)-(\\w+)/ -> "ab"' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 1);
    my $ret = print_and_return($f, $cap);
    my ($out, $ll) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'ab', '$1 is the first captured run');
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        '.ll is libperl-free');
};

subtest '$2: "ab-cd" =~ /(\\w+)-(\\w+)/ -> "cd"' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 2);
    my $ret = print_and_return($f, $cap);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'cd', '$2 is the second captured run');
};

subtest 'guarded idiom: matched ? length($1) : 0 (the realistic lib/ shape)' => sub {
    # if ($s =~ /(o+)/) { length($1) } else { 0 }  on "foo" -> 2
    my $f = _mk();
    my ($m, $cap) = capture_graph($f, 'foo', '(o+)', 1);
    my $len = $f->make('Length', inputs => [$cap]);
    $len->set_stamp('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_stamp('Int');
    my $t = $f->make('TernaryExpr', inputs => [$m, $len, $zero]);
    $t->set_stamp('Int');
    my $ret = print_and_return($f, $t);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '2', 'length($1) of the captured "oo" is 2');
};

subtest 'capture via qr-applied Match also works' => sub {
    my $f = _mk();
    my $subj = $f->make('Constant', value => 'x=42', const_type => 'string');
    $subj->set_stamp('Str');
    my $qr = $f->make('Constant', value => '(\\d+)', const_type => 'regex');
    $qr->set_stamp('Regex');
    my $m = $f->make('Match', inputs => [$subj, $qr]);
    $m->set_stamp('Boolean');
    my $cap = $f->make('RegexCapture', n => 1, inputs => [$m]);
    $cap->set_stamp('Str');
    my $ret = print_and_return($f, $cap);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, '42', '$1 through a qr-applied Match');
};

# These are GUARDS, not GAPs. `$3` against a 2-group pattern and a capture read
# from something that never matched have no right answer to produce -- refusing
# is the correct behaviour permanently, not a feature awaiting implementation.
# So they assert the DIE and what it names, not the `GAP:` prefix: that prefix
# means "perl does this, Chalk does not yet", and it is what puts a construct on
# the worklist. A guard on the worklist reads as unbuilt work that nobody will
# ever build.
subtest 'guards: out-of-range n and a non-match input die loudly' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 3);
    my $ret = $f->make_cfg('Return', inputs => [$cap]);
    eval { Chalk::Target::LLVM->lower($ret, program_mode => 1) };
    like($@, qr/out of range/,
        '$3 with a 2-group pattern dies, naming the range');

    my $f2 = _mk();
    my $c = $f2->make('Constant', value => 'x', const_type => 'string');
    $c->set_stamp('Str');
    my $cap2 = $f2->make('RegexCapture', n => 1, inputs => [$c]);
    $cap2->set_stamp('Str');
    my $ret2 = $f2->make_cfg('Return', inputs => [$cap2]);
    eval { Chalk::Target::LLVM->lower($ret2, program_mode => 1) };
    like($@, qr/not a regex match node/,
        'RegexCapture on a non-match input dies, naming the input');
};

# ---------------------------------------------------------------------------
# The NUL-termination invariant (branch review C4): every Str SSA value must
# be NUL-terminated, because length tracking is LOST at phi merges and the
# fallbacks (epilogue printf %s, strlen) assume NUL. A zero-copy view into the
# subject violates that — a capture crossing an if/else merge printed the
# subject TAIL ("abyy"). The capture is therefore COPIED to a NUL-terminated
# buffer at read time.
# ---------------------------------------------------------------------------
subtest 'capture crossing a Str phi merge prints exactly the capture' => sub {
    my $f = _mk();

    # my $s = "xxabyy"; $s =~ /x(ab)y/  ($1 = "ab")
    my $sval = $f->make('Constant', value => 'xxabyy', const_type => 'string');
    $sval->set_stamp('Str');
    my $sname = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$sname, $sval]);
    $vs->set_stamp('Str');
    my $rs = $f->make('PadAccess', targ => 0, sigil => '$', symbol => 's', inputs => [$vs]);
    $rs->set_stamp('Str');
    my $m = $f->make('RegexMatch', pattern => 'x(ab)y', flags => '', inputs => [$rs]);
    $m->set_stamp('Boolean');
    my $cap = $f->make('RegexCapture', n => 1, inputs => [$m]);
    $cap->set_stamp('Str');

    # my $x = "zz"; if (1 > 0) { $x = $1 } else { $x = "ww" } return $x
    my $zz = $f->make('Constant', value => 'zz', const_type => 'string');
    $zz->set_stamp('Str');
    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$xn, $zz]);
    $vx->set_stamp('Str');

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_stamp('Int');
    my $c0 = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_stamp('Int');
    my $cmp = $f->make('NumGt', inputs => [$c1, $c0]);
    $cmp->set_stamp('Boolean');

    my $lhs1 = $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'x', inputs => [$vx]);
    $lhs1->set_stamp('Str');
    my $as1 = $f->make('Assign', inputs => [$lhs1, $cap]);
    $as1->set_stamp('Str');

    my $ww = $f->make('Constant', value => 'ww', const_type => 'string');
    $ww->set_stamp('Str');
    my $lhs2 = $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'x', inputs => [$vx]);
    $lhs2->set_stamp('Str');
    my $as2 = $f->make('Assign', inputs => [$lhs2, $ww]);
    $as2->set_stamp('Str');

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
    my $proj0 = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1 = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);
    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    my $rx = $f->make('PadAccess', targ => 1, sigil => '$', symbol => 'x', inputs => [$vx]);
    $rx->set_stamp('Str');

    # Existing chain: vs -> vx -> if_node; the Print goes after the merge.
    $vx->set_control_in($vs);
    $if_node->set_control_in($vx);
    my $ret = print_and_return($f, $rx, $if_node);

    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'ab', 'merged capture prints exactly "ab", not the subject tail');
};

done_testing;
