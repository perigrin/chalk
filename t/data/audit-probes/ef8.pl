my $s = "aaa"; $s =~ /a/g; my $p = pos($s); pos($s) = 0; $s =~ /a/g; print "$p ", pos($s), "\n";
