my @t = localtime(0); my $y = $t[5]; print $y == 70 || $y == 69 ? "ok\n" : "bad\n";
