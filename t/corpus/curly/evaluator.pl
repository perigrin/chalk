# A tiny expression evaluator: expressions are nested array references,
# [op, left, right], evaluated, printed in infix with the fewest
# brackets, differentiated, and simplified.
use v5.42;

my %ops = (
    '+' => sub ($x, $y) { $x + $y },
    '-' => sub ($x, $y) { $x - $y },
    '*' => sub ($x, $y) { $x * $y },
    '/' => sub ($x, $y) { die "division by zero\n" if $y == 0; $x / $y },
    '^' => sub ($x, $y) { $x ** $y },
);
my %prec = ('+' => 1, '-' => 1, '*' => 2, '/' => 2, '^' => 3);

sub evaluate ($e, $env) {
    return $e unless ref $e;
    return $env->{$e->[1]} // die "unbound variable $e->[1]\n" if $e->[0] eq 'var';
    my ($op, $l, $r) = $e->@*;
    my $f = $ops{$op};
    die "unknown operator $op\n" unless defined $f;
    return $f->(evaluate($l, $env), evaluate($r, $env));
}

sub show ($e, $outer = 0) {
    return "$e" unless ref $e;
    return $e->[1] if $e->[0] eq 'var';
    my ($op, $l, $r) = $e->@*;
    my $p = $prec{$op} // 4;
    my $s = show($l, $p) . " $op " . show($r, $p + 1);
    return $p < $outer ? "($s)" : $s;
}

sub V ($name) { ['var', $name] }

sub deriv ($e, $x) {
    return 0 unless ref $e;
    if ($e->[0] eq 'var') { return $e->[1] eq $x ? 1 : 0 }
    my ($op, $l, $r) = $e->@*;
    return [$op, deriv($l, $x), deriv($r, $x)] if $op eq '+' || $op eq '-';
    return ['+', ['*', deriv($l, $x), $r], ['*', $l, deriv($r, $x)]] if $op eq '*';
    return ['*', ['*', $r, ['^', $l, $r - 1]], deriv($l, $x)] if $op eq '^' && !ref $r;
    die "can't differentiate $op\n";
}

sub simplify ($e) {
    return $e unless ref $e && $e->[0] ne 'var';
    my ($op, $l, $r) = ($e->[0], simplify($e->[1]), simplify($e->[2]));
    return evaluate([$op, $l, $r], {}) if !ref $l && !ref $r;
    if ($op eq '*') {
        return 0 if (!ref $l && $l == 0) || (!ref $r && $r == 0);
        return $r if !ref $l && $l == 1;
        return $l if !ref $r && $r == 1;
    }
    if ($op eq '+') {
        return $r if !ref $l && $l == 0;
        return $l if !ref $r && $r == 0;
    }
    return $l if $op eq '^' && !ref $r && $r == 1;
    return [$op, $l, $r];
}

my $e = ['+', ['*', 3, ['^', V('x'), 2]], ['-', ['*', 2, V('x')], 7]];
say "e = ", show($e);
for my $x (0, 1, 2, 10) {
    say "  at x = $x: ", evaluate($e, { x => $x });
}
my $d = deriv($e, 'x');
say "de/dx = ", show(simplify($d));
say "  at x = 2: ", evaluate($d, { x => 2 });

my $f = ['/', ['-', V('a'), V('b')], ['+', V('a'), V('b')]];
say "f = ", show($f), " = ", evaluate($f, { a => 3, b => 1 });

for my $bad (['/', 1, ['-', 2, 2]], ['%', 1, 2], ['+', V('y'), 1]) {
    try {
        evaluate($bad, { x => 1 });
    } catch ($err) {
        print show($bad), ": $err";
    }
}
