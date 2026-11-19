my $s = "abc"; $s =~ /(a)/; sub m2 { "q" =~ /(q)/; $1 } my $r = m2(); print "$1 $r\n";
