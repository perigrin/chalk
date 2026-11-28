my $r = eval { die "x\n" } || do { "alt" }; print "$r\n";
