my $s = "abc"; $s =~ /(a)/; my $r = [$1, $s =~ /(b)/]; print "@$r\n";
