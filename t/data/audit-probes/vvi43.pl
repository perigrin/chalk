my $s = "abc"; sub up { $_[0] = uc $_[0] } up(substr($s, 1, 1)); print "$s\n";
