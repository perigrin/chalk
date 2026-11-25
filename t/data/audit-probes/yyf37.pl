my @a; $a[2][1] = 5; print scalar(@a), scalar(@{$a[2]}), defined $a[0] ? "d" : "u", "\n";
