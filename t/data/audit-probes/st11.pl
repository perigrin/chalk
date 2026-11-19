my $s = "abc"; my $a = length($s); substr($s, 0, 1) = ""; my $b = length($s); print "$a$b\n";
