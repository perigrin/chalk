# An interpreter for Brainfuck: the program is checked for balanced
# brackets and the jumps found first, then run on a tape of 300 cells
# with a step limit; hello world, a cell-doubler, and an unbalanced one.
use v5.42;

sub compile ($src) {
    my @code = grep { index("+-<>[].,", $_) >= 0 } map { substr($src, $_, 1) } 0 .. length($src) - 1;
    my (%jump, @stack);
    for my $i (0 .. $#code) {
        if ($code[$i] eq '[') {
            push @stack, $i;
        } elsif ($code[$i] eq ']') {
            die "unmatched ] at $i\n" unless @stack;
            my $open = pop @stack;
            @jump{$open, $i} = ($i, $open);
        }
    }
    die "unmatched [ at $stack[-1]\n" if @stack;
    return (\@code, \%jump);
}

sub run ($src, $input = "") {
    my ($code, $jump) = compile($src);
    my @tape = (0) x 300;
    my ($ip, $dp, $steps, $out, $in) = (0, 0, 0, "", 0);
    while ($ip < $code->@*) {
        die "too many steps\n" if ++$steps > 100_000;
        my $op = $code->[$ip];
        if    ($op eq '+') { $tape[$dp] = ($tape[$dp] + 1) % 256 }
        elsif ($op eq '-') { $tape[$dp] = ($tape[$dp] + 255) % 256 }
        elsif ($op eq '>') { $dp++ }
        elsif ($op eq '<') { $dp-- }
        elsif ($op eq '.') { $out .= chr $tape[$dp] }
        elsif ($op eq ',') { $tape[$dp] = $in < length $input ? ord substr($input, $in++, 1) : 0 }
        elsif ($op eq '[') { $ip = $jump->{$ip} if $tape[$dp] == 0 }
        elsif ($op eq ']') { $ip = $jump->{$ip} if $tape[$dp] != 0 }
        $ip++;
    }
    return ($out, $steps);
}

my $hello = '++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.';
my ($out, $steps) = run($hello);
print $out;
say "($steps steps)";

my $reverse = '>,[>,]<[.<]';
($out, $steps) = run($reverse, "stressed");
say "reversed: $out ($steps steps)";

my $add = ',>,[<+>-]<------------------------------------------------.';
($out) = run($add, "34");
say "3 + 4 = $out";

for my $bad ('+[[-]', '+]', '+[]') {
    try {
        my ($o, $s) = run($bad);
        say "'$bad' ran in $s steps";
    } catch ($e) {
        print "'$bad': $e";
    }
}
