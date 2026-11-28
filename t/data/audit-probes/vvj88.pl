my @a = (1,2,3); my @e = (exists $a[1], exists $a[5], defined $a[1]); delete $a[1]; print scalar(grep { $_ } @e), defined $a[1] ? "d" : "u", scalar(@a), "\n";
