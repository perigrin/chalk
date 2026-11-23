"ab" =~ /(a)/; sub f { "xy" =~ /(y)/; 0 } my $v = $1; f(); print "$v $1\n";
