sub f { return } my $n = () = f(); my $v = f(); my @a = f(); print $n, defined $v ? "d" : "u", scalar(@a), "\n";
