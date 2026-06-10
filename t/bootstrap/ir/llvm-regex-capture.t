# ABOUTME: G7 $N magic-var graph edges — RegexCapture(match, n) reads capture N
# ABOUTME: as a zero-copy view into the subject via the G6 _regex_captures contract.
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

done_testing;
