"x1" =~ /(\d)/; for my $s (qw(a b)) { print $1; "y2" =~ /(\d)/ if $s eq "a" } print $1, "\n";
