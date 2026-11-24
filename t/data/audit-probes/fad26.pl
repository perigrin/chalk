my $v = eval { die "x\n"; 1 } || "dead"; print "$v\n";
