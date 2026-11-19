sub f { return } my @a = f(); my $s = f(); print scalar(@a), defined $s ? "d" : "u", "\n";
