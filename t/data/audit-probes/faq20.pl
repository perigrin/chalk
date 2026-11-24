"ab"=~/(a)/; my $r = "xy"=~/(y)/ ? $1 : "n"; print "$r$1\n";
