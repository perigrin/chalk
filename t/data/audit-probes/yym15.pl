my @a = (1,2,3); print exists $a[1] ? 1 : 0, exists $a[5] ? 1 : 0, exists $a[-1] ? 1 : 0; delete $a[1]; print defined $a[1] ? "d" : "u", scalar(@a); delete $a[-1]; print scalar(@a), "\n";
