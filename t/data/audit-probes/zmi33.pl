my @a=(1,2,3); $#a=0; print scalar(@a); $#a=2; print scalar(@a), defined $a[2] ? "d" : "u", $#a, "\n";
