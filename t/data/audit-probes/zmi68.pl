my @a=(1,2,3); delete $a[1]; print scalar(@a), defined $a[1] ? "d" : "u"; delete $a[2]; print scalar(@a), "\n";
