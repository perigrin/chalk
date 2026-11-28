my $s = "abc"; $s =~ /(a)/; my $t = $1 . ($s =~ s/(b)/z/ ? $1 : ""); print "$t\n";
