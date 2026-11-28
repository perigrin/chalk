# A state machine driven by a table of closures: a turnstile, then a
# tokenizer for a tiny language whose states are subs that read one
# character and say which state comes next.
use v5.42;

my %turnstile = (
    locked   => { coin => sub { say "  unlocked"; 'unlocked' },
                  push => sub { say "  it's locked"; 'locked' } },
    unlocked => { coin => sub { say "  coin returned"; 'unlocked' },
                  push => sub { say "  you pass"; 'locked' } },
);

my $state = 'locked';
my %count;
for my $event (qw(push coin push push coin coin push)) {
    say "$state + $event";
    my $action = $turnstile{$state}{$event};
    die "no transition for $event in $state" unless $action;
    $state = $action->();
    $count{$state}++;
}
say "ended $state; ", join(", ", map { "$_ $count{$_} times" } sort keys %count);

# The tokenizer
my @tokens;
my $buf = '';

sub kind ($c) {
    return 'end'   if $c eq '';
    return 'digit' if $c ge '0' && $c le '9';
    return 'alpha' if (lc($c) ge 'a' && lc($c) le 'z') || $c eq '_';
    return 'space' if $c eq ' ';
    return 'quote' if $c eq '"';
    return 'op';
}

my %lexer;
%lexer = (
    start => sub ($c) {
        my $k = kind($c);
        return 'done'   if $k eq 'end';
        return 'start'  if $k eq 'space';
        if ($k eq 'digit') { $buf = $c;  return 'number' }
        if ($k eq 'alpha') { $buf = $c;  return 'word' }
        if ($k eq 'quote') { $buf = '';  return 'string' }
        push @tokens, "OP($c)";
        return 'start';
    },
    number => sub ($c) {
        if (kind($c) eq 'digit') { $buf .= $c; return 'number' }
        push @tokens, "NUM($buf)";
        return $lexer{start}->($c);
    },
    word => sub ($c) {
        my $k = kind($c);
        if ($k eq 'alpha' || $k eq 'digit') { $buf .= $c; return 'word' }
        push @tokens, "WORD($buf)";
        return $lexer{start}->($c);
    },
    string => sub ($c) {
        die "unterminated string\n" if $c eq '';
        if ($c eq '"') { push @tokens, "STR($buf)"; return 'start' }
        $buf .= $c;
        return 'string';
    },
);

for my $src ('x1 = 42 + y_2*(7-z)', 'say "hi there", 3', 'if n>10 "big"', 'oops "open') {
    @tokens = ();
    my $st = 'start';
    try {
        for my $i (0 .. length $src) {
            $st = $lexer{$st}->(substr($src, $i, 1));
        }
        print "$src\n  => @tokens\n";
    } catch ($e) {
        print "$src: $e";
    }
}
