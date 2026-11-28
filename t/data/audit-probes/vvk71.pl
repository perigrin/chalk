my $s = ""; my $i = 0; $s .= $i++ while $i < 3; $s .= $i-- until $i == 0; print "$s\n";
