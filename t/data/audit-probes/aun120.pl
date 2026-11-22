my $s="aab"; $s =~ /a/g; my $p = pos($s); $s =~ /a/g; print "$p ", pos($s), "\n";
