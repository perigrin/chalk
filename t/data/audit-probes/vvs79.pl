my $s = "abc"; $s =~ /(a)/; my %h = (k => $1, m => scalar($s =~ /(b)/)); print $h{k}, "\n";
