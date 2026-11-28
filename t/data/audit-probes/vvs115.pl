my $s = "abc"; $s =~ /(a)/; my $c = sub { "x" =~ /(x)/; $1 }; my $t = $c->(); print "$t$1\n";
