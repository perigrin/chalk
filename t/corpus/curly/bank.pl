# A bank simulation: each account is a set of closures over its own
# balance and history; errors are thrown with die and caught with try;
# a transfer undoes itself when its second half fails.
use v5.42;

my %accounts;

sub open_account ($name, $balance = 0, $limit = 0) {
    die "account $name already exists\n" if exists $accounts{$name};
    my @history;
    my $acct = {
        name    => sub () { $name },
        balance => sub () { $balance },
        deposit => sub ($amount) {
            die "deposit must be positive, not $amount\n" unless $amount > 0;
            $balance += $amount;
            push @history, "+$amount";
            return $balance;
        },
        withdraw => sub ($amount) {
            die "withdrawal must be positive, not $amount\n" unless $amount > 0;
            my $short = $balance - $amount < -$limit;
            die sprintf("%s has %d, can't take %d\n", $name, $balance, $amount) if $short;
            $balance -= $amount;
            push @history, "-$amount";
            return $balance;
        },
        history => sub () { @history },
    };
    $accounts{$name} = $acct;
    return $acct;
}

sub account ($name) {
    return $accounts{$name} // die "no account called $name\n";
}

sub transfer ($from, $to, $amount) {
    my $src = account($from);
    my $dst = account($to);
    $src->{withdraw}->($amount);
    try {
        $dst->{deposit}->($amount);
    } catch ($e) {
        $src->{deposit}->($amount);
        die "transfer undone: $e";
    }
    return;
}

sub attempt ($what, $code) {
    try {
        $code->();
        say "ok:     $what";
    } catch ($e) {
        print "failed: $what: $e";
    }
}

open_account("alice", 100);
open_account("bob", 20, 50);
open_account("carol");

attempt("alice pays bob 30",  sub { transfer("alice", "bob", 30) });
attempt("bob pays carol 90",  sub { transfer("bob", "carol", 90) });
attempt("bob pays carol 20",  sub { transfer("bob", "carol", 20) });
attempt("carol pays dave 5",  sub { transfer("carol", "dave", 5) });
attempt("alice pays carol -5", sub { transfer("alice", "carol", -5) });
attempt("open alice again",   sub { open_account("alice") });
attempt("carol deposits 0",   sub { account("carol")->{deposit}->(0) });

for my $name (sort keys %accounts) {
    my $a1 = $accounts{$name};
    printf "%-6s %5d  %s\n", $name, $a1->{balance}->(), join(" ", $a1->{history}->()) || "(none)";
}

my $total = 0;
$total += $accounts{$_}->{balance}->() for sort keys %accounts;
say "money in the bank: $total";

# Interest, month by month, on a copy of the balances
my %bal = map { ($_ => $accounts{$_}->{balance}->()) } sort keys %accounts;
for my $month (1 .. 3) {
    for my $name (sort keys %bal) {
        $bal{$name} = $bal{$name} > 0 ? $bal{$name} * 1.01 : $bal{$name} * 1.02;
    }
    say "month $month: ", join("  ", map { sprintf "%s %.2f", $_, $bal{$_} } sort keys %bal);
}
