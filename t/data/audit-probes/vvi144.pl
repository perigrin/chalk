my $s = "abc"; my $t = ord($s) . chr(ord($s) + 1) . ord(substr($s, 1)); print "$t\n";
