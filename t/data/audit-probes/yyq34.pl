sub set { $_[0] = "ZZ" } my $s="abc"; set(substr($s,0,1)); print "$s\n";
