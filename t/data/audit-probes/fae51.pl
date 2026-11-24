my $x=1; if (eval { die "a\n"; 1 }) { $x=2 } else { $x=3 } print "$x\n";
