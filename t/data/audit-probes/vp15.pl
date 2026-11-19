my @q = (1,2,3); my $got = ""; $got .= $_ while defined($_ = shift @q); print "$got\n";
