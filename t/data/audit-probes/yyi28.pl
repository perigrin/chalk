sub nop { } my %h; nop($h{a}); my @a; nop($a[2]); print exists $h{a} ? 1 : 0, scalar(@a), "\n";
