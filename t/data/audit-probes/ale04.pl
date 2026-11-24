my @a; for ($a[1], $a[3]) { $_ = 1 } print scalar(@a), defined $a[0] ? 1 : 0, "\n";
