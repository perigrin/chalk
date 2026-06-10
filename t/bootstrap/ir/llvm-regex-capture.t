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

# Build: $subject =~ /$pattern/ then RegexCapture(match, $n).
sub capture_graph {
    my ($f, $subject, $pattern, $n) = @_;
    my $subj = $f->make('Constant', value => $subject, const_type => 'string');
    $subj->set_representation('Str');
    my $m = $f->make('RegexMatch', pattern => $pattern, flags => '', inputs => [$subj]);
    $m->set_representation('Bool');
    my $cap = $f->make('RegexCapture', n => $n, inputs => [$m]);
    $cap->set_representation('Str');
    return ($m, $cap);
}

subtest '$1: "ab-cd" =~ /(\\w+)-(\\w+)/ -> Str:ab' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 1);
    my $ret = $f->make_cfg('Return', inputs => [$cap]);
    my ($out, $ll) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Str:ab', '$1 is the first captured run');
    ok($ll !~ /Perl_|(?<![A-Za-z0-9_])SV(?![A-Za-z0-9_])|sv_|libperl|\bAV\b|\bHV\b/,
        '.ll is libperl-free');
};

subtest '$2: "ab-cd" =~ /(\\w+)-(\\w+)/ -> Str:cd' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 2);
    my $ret = $f->make_cfg('Return', inputs => [$cap]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Str:cd', '$2 is the second captured run');
};

subtest 'guarded idiom: matched ? length($1) : 0 (the realistic lib/ shape)' => sub {
    # if ($s =~ /(o+)/) { length($1) } else { 0 }  on "foo" -> 2
    my $f = _mk();
    my ($m, $cap) = capture_graph($f, 'foo', '(o+)', 1);
    my $len = $f->make('Length', inputs => [$cap]);
    $len->set_representation('Int');
    my $zero = $f->make('Constant', value => '0', const_type => 'integer');
    $zero->set_representation('Int');
    my $t = $f->make('TernaryExpr', inputs => [$m, $len, $zero]);
    $t->set_representation('Int');
    my $ret = $f->make_cfg('Return', inputs => [$t]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Int:2', 'length($1) of the captured "oo" is 2');
};

subtest 'capture via qr-applied Match also works' => sub {
    my $f = _mk();
    my $subj = $f->make('Constant', value => 'x=42', const_type => 'string');
    $subj->set_representation('Str');
    my $qr = $f->make('Constant', value => '(\\d+)', const_type => 'regex');
    $qr->set_representation('Regex');
    my $m = $f->make('Match', inputs => [$subj, $qr]);
    $m->set_representation('Bool');
    my $cap = $f->make('RegexCapture', n => 1, inputs => [$m]);
    $cap->set_representation('Str');
    my $ret = $f->make_cfg('Return', inputs => [$cap]);
    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Str:42', '$1 through a qr-applied Match');
};

subtest 'guards: out-of-range n and a non-match input die GAP' => sub {
    my $f = _mk();
    my (undef, $cap) = capture_graph($f, 'ab-cd', '(\\w+)-(\\w+)', 3);
    my $ret = $f->make_cfg('Return', inputs => [$cap]);
    eval { Chalk::Target::LLVM->lower($ret) };
    like($@, qr/GAP/, '$3 with a 2-group pattern dies GAP');

    my $f2 = _mk();
    my $c = $f2->make('Constant', value => 'x', const_type => 'string');
    $c->set_representation('Str');
    my $cap2 = $f2->make('RegexCapture', n => 1, inputs => [$c]);
    $cap2->set_representation('Str');
    my $ret2 = $f2->make_cfg('Return', inputs => [$cap2]);
    eval { Chalk::Target::LLVM->lower($ret2) };
    like($@, qr/GAP/, 'RegexCapture on a non-match input dies GAP');
};

# ---------------------------------------------------------------------------
# The NUL-termination invariant (branch review C4): every Str SSA value must
# be NUL-terminated, because length tracking is LOST at phi merges and the
# fallbacks (epilogue printf %s, strlen) assume NUL. A zero-copy view into the
# subject violates that — a capture crossing an if/else merge printed the
# subject TAIL (Str:abyy). The capture is therefore COPIED to a NUL-terminated
# buffer at read time.
# ---------------------------------------------------------------------------
subtest 'capture crossing a Str phi merge prints exactly the capture' => sub {
    my $f = _mk();

    # my $s = "xxabyy"; $s =~ /x(ab)y/  ($1 = "ab")
    my $sval = $f->make('Constant', value => 'xxabyy', const_type => 'string');
    $sval->set_representation('Str');
    my $sname = $f->make('Constant', value => '$s', const_type => 'string');
    my $vs = $f->make('VarDecl', inputs => [$sname, $sval]);
    $vs->set_representation('Str');
    my $rs = $f->make('PadAccess', targ => 0, varname => '$s', inputs => [$vs]);
    $rs->set_representation('Str');
    my $m = $f->make('RegexMatch', pattern => 'x(ab)y', flags => '', inputs => [$rs]);
    $m->set_representation('Bool');
    my $cap = $f->make('RegexCapture', n => 1, inputs => [$m]);
    $cap->set_representation('Str');

    # my $x = "zz"; if (1 > 0) { $x = $1 } else { $x = "ww" } return $x
    my $zz = $f->make('Constant', value => 'zz', const_type => 'string');
    $zz->set_representation('Str');
    my $xn = $f->make('Constant', value => '$x', const_type => 'string');
    my $vx = $f->make('VarDecl', inputs => [$xn, $zz]);
    $vx->set_representation('Str');

    my $c1 = $f->make('Constant', value => '1', const_type => 'integer');
    $c1->set_representation('Int');
    my $c0 = $f->make('Constant', value => '0', const_type => 'integer');
    $c0->set_representation('Int');
    my $cmp = $f->make('NumGt', inputs => [$c1, $c0]);
    $cmp->set_representation('Bool');

    my $lhs1 = $f->make('PadAccess', targ => 1, varname => '$x', inputs => [$vx]);
    $lhs1->set_representation('Str');
    my $as1 = $f->make('Assign', inputs => [$lhs1, $cap]);
    $as1->set_representation('Str');

    my $ww = $f->make('Constant', value => 'ww', const_type => 'string');
    $ww->set_representation('Str');
    my $lhs2 = $f->make('PadAccess', targ => 1, varname => '$x', inputs => [$vx]);
    $lhs2->set_representation('Str');
    my $as2 = $f->make('Assign', inputs => [$lhs2, $ww]);
    $as2->set_representation('Str');

    my $if_node = $f->make('If', inputs => [$vx, $cmp]);
    my $proj0 = $f->make('Proj', inputs => [$if_node], index => 0);
    my $proj1 = $f->make('Proj', inputs => [$if_node], index => 1);
    my $region = $f->make('Region', inputs => [$proj0, $proj1]);
    $if_node->set_region($region);
    $as1->set_control_in($proj0);
    $as2->set_control_in($proj1);

    my $rx = $f->make('PadAccess', targ => 1, varname => '$x', inputs => [$vx]);
    $rx->set_representation('Str');

    my $ret = $f->make_cfg('Return', inputs => [$rx]);
    $vx->set_control_in($vs);
    $if_node->set_control_in($vx);
    $ret->set_control_in($if_node);

    my ($out) = eval { lli_run($ret) };
    ok(!$@, 'lowering + lli succeeded') or do { diag("error: $@"); return };
    is($out, 'Str:ab', 'merged capture prints exactly "ab", not the subject tail');
};

done_testing;
