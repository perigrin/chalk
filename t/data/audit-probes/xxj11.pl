my $s = "aaa"; $s =~ /a/g; pos($s) = 0; $s =~ /a/g; print pos($s), "\n";
