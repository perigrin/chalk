"abc"=~/(b)/; sub m2 { "xyz"=~/(y)/; $1 } my $r=m2(); print "$r$1\n";
