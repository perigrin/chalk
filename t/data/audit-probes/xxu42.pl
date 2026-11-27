our $x = 1; sub c { $x = 3; 3 } my $s = ($x <=> c()) . ($x cmp c()); print "$s\n";
