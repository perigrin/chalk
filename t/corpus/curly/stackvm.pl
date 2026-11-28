# A small stack machine: an assembler from text with labels, and an
# interpreter with a dispatch table of closures; it runs a factorial
# loop, a countdown, and a program that faults on purpose.
use v5.42;

# No split and no regexes yet (steps 19 and 20): the words of a line,
# up to a '#', split at blanks.
sub words ($line) {
    my $hash = index($line, "#");
    $line = substr($line, 0, $hash) if $hash >= 0;
    my (@w, $word);
    for my $i (0 .. length $line) {
        my $c = substr($line, $i, 1);
        if ($c ne "" && $c ne " ") { $word = ($word // "") . $c; next }
        push @w, $word if defined $word;
        $word = undef;
    }
    return @w;
}

sub is_int ($s) {
    my $start = substr($s, 0, 1) eq "-" ? 1 : 0;
    return 0 if length($s) == $start;
    for my $i ($start .. length($s) - 1) {
        my $c = substr($s, $i, 1);
        return 0 unless $c ge "0" && $c le "9";
    }
    return 1;
}

sub assemble ($src) {
    my %labels;
    my (@code, @fixups);
    my $pos = 0;
    while ($pos < length $src) {
        my $nl = index($src, "\n", $pos);
        $nl = length $src if $nl < 0;
        my @w = words(substr($src, $pos, $nl - $pos));
        $pos = $nl + 1;
        if (@w && substr($w[0], -1) eq ":") {
            my $label = shift @w;
            $labels{substr($label, 0, length($label) - 1)} = scalar(@code);
        }
        next unless @w;
        my ($op, $arg) = @w;
        push @fixups, scalar(@code) if defined $arg && !is_int($arg);
        push @code, [$op, $arg];
    }
    for my $i (@fixups) {
        my $name = $code[$i][1];
        die "no label '$name'\n" unless exists $labels{$name};
        $code[$i][1] = $labels{$name};
    }
    return \@code;
}

sub run ($code, $limit = 10_000) {
    my %mem;
    my (@stack, @out);
    my $pc = 0;
    my $steps = 0;
    my $pop = sub () { die "stack underflow at $pc\n" unless @stack; pop @stack };
    my %ops = (
        push  => sub ($a1) { push @stack, $a1 },
        pop   => sub ($a1) { $pop->() },
        dup   => sub ($a1) { my $x = $pop->(); push @stack, $x, $x },
        swap  => sub ($a1) { my $y = $pop->(); my $x = $pop->(); push @stack, $y, $x },
        add   => sub ($a1) { my $y = $pop->(); push @stack, $pop->() + $y },
        sub   => sub ($a1) { my $y = $pop->(); push @stack, $pop->() - $y },
        mul   => sub ($a1) { my $y = $pop->(); push @stack, $pop->() * $y },
        store => sub ($a1) { $mem{$a1} = $pop->() },
        load  => sub ($a1) { push @stack, $mem{$a1} // 0 },
        print => sub ($a1) { push @out, $pop->() },
        jmp   => sub ($a1) { $pc = $a1 - 1 },
        jz    => sub ($a1) { $pc = $a1 - 1 if $pop->() == 0 },
        halt  => sub ($a1) { $pc = $code->@* },
    );
    while ($pc < $code->@*) {
        die "step limit reached\n" if ++$steps > $limit;
        my ($op, $arg) = @{ $code->[$pc] };
        my $f = $ops{$op} // die "unknown instruction '$op' at $pc\n";
        $f->($arg);
        $pc++;
    }
    return ("@out", $steps);
}

my %programs = (
    factorial => <<'END',
        push 1
        store 0        # acc
        push 10
        store 1        # n
loop:   load 1
        jz done
        load 0
        load 1
        mul
        store 0
        load 1
        push 1
        sub
        store 1
        jmp loop
done:   load 0
        print
END
    countdown => <<'END',
        push 5
top:    dup
        print
        push 1
        sub
        dup
        jz end
        jmp top
end:    halt
END
    broken => "push 1\nadd\n",
    forever => "x: jmp x\n",
    missing => "jmp nowhere\n",
);

for my $name (sort keys %programs) {
    try {
        my $code = assemble($programs{$name});
        my ($out, $steps) = run($code);
        say "$name: $out ($steps steps, ", scalar($code->@*), " instructions)";
    } catch ($e) {
        print "$name: $e";
    }
}
