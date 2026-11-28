# A reverse Polish calculator with a dispatch table, then a shunting-yard
# converter from infix to RPN, so infix expressions are evaluated too.
use v5.42;

my %binary = (
    '+' => sub ($x, $y) { $x + $y },
    '-' => sub ($x, $y) { $x - $y },
    '*' => sub ($x, $y) { $x * $y },
    '/' => sub ($x, $y) { die "division by zero\n" if $y == 0; $x / $y },
    '^' => sub ($x, $y) { $x ** $y },
);
my %unary = (
    neg => sub ($x) { -$x },
    dup => undef,
);

# No split yet (step 20): the words between blanks.
sub tokens ($s) {
    my @t;
    my $pos = 0;
    while ($pos < length $s) {
        my $blank = index($s, " ", $pos);
        $blank = length $s if $blank < 0;
        push @t, substr($s, $pos, $blank - $pos) if $blank > $pos;
        $pos = $blank + 1;
    }
    return @t;
}

# No regexes yet (step 19): digits, with at most one point among them.
sub is_number ($s) {
    my ($digits, $points) = (0, 0);
    for my $i (0 .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        if ($c eq '.') { $points++ } elsif ($c ge '0' && $c le '9') { $digits++ } else { return 0 }
    }
    return $digits > 0 && $points <= 1;
}

sub rpn ($expr) {
    my @stack;
    for my $tok (tokens($expr)) {
        if (exists $binary{$tok}) {
            die "stack underflow at '$tok'\n" if @stack < 2;
            my $y = pop @stack;
            my $x = pop @stack;
            push @stack, $binary{$tok}->($x, $y);
        } elsif ($tok eq 'neg') {
            die "stack underflow at '$tok'\n" unless @stack;
            push @stack, $unary{neg}->(pop @stack);
        } elsif ($tok eq 'dup') {
            die "stack underflow at '$tok'\n" unless @stack;
            push @stack, $stack[-1];
        } elsif (is_number($tok)) {
            push @stack, $tok;
        } else {
            die "unknown token '$tok'\n";
        }
    }
    die "expected one value, the stack holds " . scalar(@stack) . "\n" unless @stack == 1;
    return $stack[0];
}

my %prec = ('+' => 1, '-' => 1, '*' => 2, '/' => 2, '^' => 3);
my %right = ('^' => 1);

sub to_rpn ($infix) {
    my (@out, @ops);
    for my $tok (tokens($infix)) {
        if ($tok eq '(') {
            push @ops, $tok;
        } elsif ($tok eq ')') {
            push @out, pop @ops while @ops && $ops[-1] ne '(';
            die "unbalanced )\n" unless @ops;
            pop @ops;
        } elsif (exists $prec{$tok}) {
            while (@ops && $ops[-1] ne '(' &&
                   ($prec{$ops[-1]} > $prec{$tok} || ($prec{$ops[-1]} == $prec{$tok} && !$right{$tok}))) {
                push @out, pop @ops;
            }
            push @ops, $tok;
        } else {
            push @out, $tok;
        }
    }
    while (@ops) {
        my $op = pop @ops;
        die "unbalanced (\n" if $op eq '(';
        push @out, $op;
    }
    return join " ", @out;
}

for my $e ("3 4 +", "5 1 2 + 4 * + 3 -", "2 3 ^ dup *", "10 neg 4 /", "1 +", "1 2", "4 0 /", "2 x +") {
    try {
        say "$e => ", rpn($e);
    } catch ($err) {
        print "$e => error: $err";
    }
}

for my $infix ("3 + 4 * 2 / ( 1 - 5 ) ^ 2 ^ 3", "( 1 + 2 ) * ( 3 + 4 )", "2 ^ 3 ^ 2", "100 - 10 - 1", "( 1 + 2") {
    try {
        my $r = to_rpn($infix);
        say "$infix  ->  $r  =  ", rpn($r);
    } catch ($err) {
        print "$infix => error: $err";
    }
}
