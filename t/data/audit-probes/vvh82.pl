my $s = "p" . (eval { die "x\n" } // "u") . "s"; print "$s\n";
