sub m1 { "q" =~ /(q)/; $1 } "a" =~ /(a)/; my $r = m1(); print $r, $1, "\n";
